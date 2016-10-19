{CompositeDisposable} = require 'atom'
{EventEmitter} = require 'events'
path = require 'path'
helpers = require 'atom-linter'

module.exports = Language1cBSL =
  subscriptions: null

  activate: (state) ->

    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.commands.add 'atom-text-editor', 'language-1c-bsl:addpipe': => @addpipe()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'language-1c-bsl:addSlashes': => @addSlashes()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'language-1c-bsl:expandAbbreviation': => @expandAbbreviation()

    @subscriptions.add atom.config.observe 'language-1c-bsl.enableOneScriptLinter', (@enableOneScriptLinter) =>
    @subscriptions.add atom.config.observe 'language-1c-bsl.onescriptPath', (@onescriptPath) =>
    @subscriptions.add atom.config.observe 'language-1c-bsl.lintOtherExtensions', (@lintOtherExtensions) =>
    @subscriptions.add atom.config.observe 'language-1c-bsl.linterEntryPoint', (@linterEntryPoint) =>
    @subscriptions.add atom.config.observe 'language-1c-bsl.forceEnableExtendedUnicodeSupport', (enableExtendedUnicodeSupport) ->
      atom.config.set('autocomplete-plus.enableExtendedUnicodeSupport', enableExtendedUnicodeSupport)

  deactivate: ->
    @subscriptions.dispose()

  addpipe: ->
    editor = atom.workspace.getActiveTextEditor()
    cursorPos = editor.getLastCursor().getBufferPosition()
    beginRow = editor.getLastCursor().getCurrentLineBufferRange().start
    textRow = editor.getTextInBufferRange([beginRow, cursorPos])
    editor.insertText '\n'
    Reg1 = /^\s*\|([^\"]|\"[^\"]*\")*$/
    Reg2 = /^([^\|\"]|\"[^\"]*\")*\"[^\"]*$/
    if (Reg1.exec(textRow) isnt null) or (Reg2.exec(textRow) isnt null)
      editor.insertText '|'

  addSlashes: ->
    editor = atom.workspace.getActiveTextEditor()
    cursorPos = editor.getLastCursor().getBufferPosition()
    beginRow = editor.getLastCursor().getCurrentLineBufferRange().start
    textRow = editor.getTextInBufferRange([beginRow, cursorPos])
    editor.insertText '\n'
    RegComment = /^.*\/\/.*$/
    if RegComment.exec(textRow) isnt null
      editor.insertText '//'

  expandAbbreviation: ->
    editor = atom.workspace.getActiveTextEditor()
    if  editor.getSelectedText()
      atom.commands.dispatch(atom.views.getView(editor), 'editor:indent')
      return
    cursorPos = editor.getLastCursor().getBufferPosition()
    translatedPos = cursorPos.translate([0, -2])
    lastTwo = editor.getTextInBufferRange([translatedPos, cursorPos])
    buffer = editor.getTextInBufferRange([editor.getLastCursor().getCurrentLineBufferRange().start, translatedPos])
    match = buffer.match(new RegExp("([\\w_а-яё]+\\s?)$", "i"))
    if ((lastTwo == '++' || lastTwo == '--' || lastTwo == '+=' || lastTwo == '-=' || lastTwo == '*=' || lastTwo == '/=' || lastTwo == '%=') && match isnt null)
      postfix = " + 1;"
      if (lastTwo == '--')
        postfix = " - 1;"
      else if (lastTwo == '+=')
        postfix = " + "
      else if (lastTwo == '-=')
        postfix = " - "
      else if (lastTwo == '*=')
        postfix = " * "
      else if (lastTwo == '/=')
        postfix = " / "
      else if (lastTwo == '%=')
        postfix = " % "
      lengthMatch = match[1].length
      beginMatch = translatedPos.translate([0, - lengthMatch])
      editor.setTextInBufferRange([beginMatch, cursorPos], match[1] + " = " + match[1] + postfix)
    else
      editor.insertText '\t'

  getCommandId: ->
    if not @onescriptPath or @onescriptPath.length is 0
      command = "oscript"
    else
      command = @onescriptPath

    command

  provideLinter: ->
    name: 'OneScriptLint'
    grammarScopes: ['source.bsl']
    scope: 'file'
    lintOnFly: true # false for lint only on save

    lint: (textEditor) =>
      return [] unless @enableOneScriptLinter

      filePath = textEditor.getPath()
      arrFilePath = filePath.split(".")
      return [] if arrFilePath.length == 0

      extension = arrFilePath[arrFilePath.length - 1]
      if extension isnt "os" and not @lintOtherExtensions.includes(extension)
        return []

      # Arguments to checkstyle
      args = []
      args = args.concat(["-encoding=utf-8", "-check", filePath])
      if @linterEntryPoint
        project_path = ''
        filePath = atom.workspace.getActiveTextEditor().getPath()
        projectPaths = atom.project.getPaths()
        for projectPath in projectPaths
          if filePath.indexOf(projectPath) > -1
            if fs.statSync(projectPath).isDirectory()
              project_path = projectPath
            else
              project_path = path.join(projectPath, '..')
            break
        args.push("-env=" + path.join(project_path, @linterEntryPoint))

      # Execute checkstyle
      helpers.exec(@getCommandId(), args, {stream: 'stdout', throwOnStdErr: false, ignoreExitCode: true})
        .then (val) => @parse(val, textEditor)

  parse: (checkstyleOutput, textEditor) ->
    # Regex to match the error/warning line
    regex = /^\{Модуль\s+(.*)\s\/\s.*:\s+(\d+)\s+\/\s+(.*)\}/
    # Split into lines
    lines = checkstyleOutput.split /\r?\n/
    messages = []
    for line in lines

      if line.match regex
        [file, lineNum, mess] = line.match(regex)[1..3]

        type = "error"

        messages.push
          type: type       # Should be "error" or "warning"
          text: mess       # The error message
          filePath: file   # Full path to file
          range: [[lineNum - 1, 0], [lineNum - 1, Infinity]]
    return messages

  provideBuilder: ->
    class Language1cBSLBuildProvider extends EventEmitter

      constructor: (@cwd) ->
        @subscriptions = new CompositeDisposable
        @subscriptions.add atom.config.observe 'language-1c-bsl.onescriptPath', (@onescriptPath) =>

      getCommandId: ->
        if not @onescriptPath or @onescriptPath.length is 0
          command = "oscript"
        else
          command = @onescriptPath

        command

      getNiceName: ->
        '1C (BSL)'

      isEligible: ->
        yes

      settings: ->
        [
          run =
            name: 'OneScript: run',
            sh: false,
            exec: @getCommandId(),
            args: [ '-encoding=utf-8', '{FILE_ACTIVE}' ],
            errorMatch: [
                '{Модуль (?<file>[^/]+) / Ошибка в строке: (?<line>[0-9]+) / (?<message>.*)'
            ]

          check =
            name: 'OneScript: check',
            sh: false,
            exec: @getCommandId(),
            args: [ '-encoding=utf-8', '-check', '{FILE_ACTIVE}' ],
            errorMatch: [
                '{Модуль (?<file>[^/]+) / Ошибка в строке: (?<line>[0-9]+) / (?<message>.*)'
            ]

          compile =
            name: 'OneScript: compile',
            sh: false,
            exec: @getCommandId(),
            args: [ '-encoding=utf-8', '-compile', '{FILE_ACTIVE}' ],
            errorMatch: [
                '{Модуль (?<file>[^/]+) / Ошибка в строке: (?<line>[0-9]+) / (?<message>.*)'
            ]

          make =
            name: 'OneScript: make',
            sh: false,
            exec: @getCommandId(),
            args: [ '-encoding=utf-8', '-make', '{FILE_ACTIVE}', '{FILE_ACTIVE_NAME_BASE}.exe' ],
            errorMatch: [
                '{Модуль (?<file>[^/]+) / Ошибка в строке: (?<line>[0-9]+) / (?<message>.*)'
            ]

        ]
