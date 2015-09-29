_       = require 'underscore'
log     = require 'simplog'
path    = require 'path'


attachResponder = (context, res) ->
  if context.httpTransport is 'simple'
    attachSimpleResponder(context, res)
  else
    attachStandardResponder(context, res)

attachSimpleResponder = (context, res) ->
  delim = ""
  resultElementDelimiter = ""
  responseObjectDelimiter = ""
  stack = []

  c = context
  res.header 'Content-Type', 'application/javascript'
  res.write "{\"results\":["
  stack.unshift( () -> res.write "]}" )

  completeResponse = () ->
    item() while item = stack.shift()
    res.end()

  writeResultElement = (obj) ->
    res.write "#{resultElementDelimiter}#{JSON.stringify obj}"
    resultElementDelimiter = ","

  writeResponseObjectElement = (str) ->
    res.write "#{responseObjectDelimiter}#{str}"

  c.on 'row', (row) ->
    delete(row['queryId'])
    columns = {}
    _.map(row.columns, (e, i, l) -> columns[l[i].name || 'undefiend'] = l[i].value)
    writeResultElement columns

  c.on 'beginrowset', (d={}) ->
    writeResponseObjectElement "["
    responseObjectDelimiter = ""
    resultElementDelimiter = ""

  c.on 'endrowset', (d={}) ->
    writeResponseObjectElement "]"
    responseObjectDelimiter = ","

  c.on 'data', (data) ->
    writeResultElement data

  c.on 'error', (err) ->
    d = message: 'error', errorDetail: err
    d.error = err.message if err.message
    log.error err
    writeResultElement d

  c.once 'completequeryexecution', completeResponse

attachStandardResponder = (context, res) ->
  delim = ""
  indent = ""
  stack = []
  increaseIndent = () -> indent = indent + "  "
  decreaseIndent = () -> indent = indent[0...-2]

  c = context
  res.header 'Content-Type', 'application/javascript'
  res.write "{\n  \"events\":[\n"
  stack.unshift( () -> res.write "\n#{indent}]\n}\n" )
  increaseIndent()

  completeResponse = () ->
    item() while item = stack.shift()
    res.end()

  writeEvent = (evt) ->
    res.write "#{delim}#{indent}#{JSON.stringify evt}"
    delim = ",\n"

  c.on 'row', (row) ->
    row.message = 'row'
    writeEvent row

  c.on 'beginquery', (d={}) ->
    d.message = 'beginquery'
    writeEvent d

  c.on 'endquery', (d={}) ->
    d.message = 'endquery'
    writeEvent d

  c.on 'beginrowset', (d={}) ->
    d.message = 'beginrowset'
    writeEvent d

  c.on 'endrowset', (d={}) ->
    d.message = 'endrowset'
    writeEvent d

  c.on 'data', (data) ->
    data.message = 'data'
    writeEvent data

  c.on 'error', (err) ->
    d = message: 'error', errorDetail: err
    d.error = err.message if err.message
    log.error err
    writeEvent d

  c.once 'completequeryexecution', completeResponse


getQueryRequestInfo = (req, useSecure) ->
  templatePath = req.path.replace(/\.\./g, '').replace(/^\//, '')
  pathParts = templatePath.split('/')
  # If we're using a key secured client, the key must be before the connection name
  if useSecure
    clientKey = pathParts.shift()
  if pathParts[0] is 'simple_transport'
    pathParts.shift()
    transport = 'simple'
  else
    transport = 'standard'
  connectionName = pathParts.shift()
  connection = null
  if connectionName is 'header'
    # we allow an inbound connection header to override any other method
    # of selecting a connection
    connection = JSON.parse(@req.get('X-DB-CONNECTION') || null)
  templatePath = path.join.apply(path.join, pathParts)
  params = _.extend({}, req.body, req.query, req.headers)
  returnThis =
    connectionName: connectionName
    connectionConfig: connection
    templateContext: params
    templateName: templatePath
    clientKey: clientKey
    httpTransport: transport

module.exports.attachResponder = attachResponder
module.exports.getQueryRequestInfo = getQueryRequestInfo
