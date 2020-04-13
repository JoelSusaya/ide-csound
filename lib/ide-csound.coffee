{CompositeDisposable} = require 'atom'
csound = require 'csound-api'
fs = require 'fs-plus'
path = require 'path'
HelpElement = require './help-element'
MessageHistoryElement = require './message-history-element'
MessageManager = require './message-manager'

module.exports =
Csound =
  config:
    CSDOCDIR:
      title: 'Directory containing Csound’s manual in HTML'
      type: 'string'
      description: 'Csound’s `CSDOCDIR` environment variable'
      default: ''
    SADIR:
      title: 'Default directory for saving analysis files'
      type: 'string'
      description: 'Csound’s `SADIR` environment variable'
      default: '~/Documents'
    SFDIR:
      title: 'Default directory for saving sound files'
      type: 'string'
      description: 'Csound’s `SFDIR` environment variable'
      default: '~/Documents'
    SSDIR:
      title: 'Default directory for loading sound and MIDI files'
      type: 'string'
      description: 'Csound’s `SSDIR` environment variable'
      default: '~/Documents'

  activate: (state) ->
    csound.SetGlobalEnv 'SFDIR', fs.normalize(atom.config.get('ide-csound.SFDIR'))
    @Csound = csound.Create()
    @messageManager = new MessageManager(csound, @Csound)

    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.commands.add 'atom-workspace', 'ide-csound:run': => @run()
    @subscriptions.add atom.commands.add 'atom-workspace', 'ide-csound:stop': => @stop()
    @subscriptions.add atom.commands.add 'atom-workspace', 'ide-csound:show-help-for-selected-opcode': => @showHelpForSelectedOpcode()

  deactivate: ->
    @subscriptions.dispose()

  run: ->
    editor = atom.workspace.getActiveTextEditor()
    return unless editor
    previousActivePane = atom.workspace.getActivePane()
    messageHistoryElement = new MessageHistoryElement
    messageHistoryElement.initialize @messageManager, editor
    atom.workspace.activateNextPane()
    atom.workspace.getActivePane().addItem(messageHistoryElement)
    previousActivePane.activate()

    perform = (result) =>
      if result isnt csound.SUCCESS
        csound.Reset @Csound
        return
      result = csound.Start @Csound
      if result is csound.SUCCESS
        csound.PerformAsync @Csound, (result) =>
          csound.Reset @Csound
      else
        csound.Reset @Csound

    switch editor.getGrammar().name
      when 'Csound Document'
        disposable = editor.onDidSave =>
          # The Csound API function csoundCompileCsd can call csoundCompile,
          # which calls csoundStart
          # (https://github.com/csound/csound/blob/develop/Top/main.c#L494). The
          # API function csoundCompileCsdText added in commit 6770316
          # (https://github.com/csound/csound/commit/6770316cd9fd6e9c55f9730910a0a6c09a671c20)
          # calls csoundCompileCsd with the path of a temporary CSD file. The
          # API function csoundCompileArgs seems to be the only way to compile a
          # CSD file without also starting Csound.
          perform csound.CompileArgs(@Csound, ['csound', editor.getPath()])
          disposable.dispose()
        editor.save()
      else
        perform csound.CompileOrc(@Csound, editor.getText())

  stop: ->
    csound.Stop @Csound

  showHelpForOpcode: (opcodeName) ->
    filename = if opcodeName is '0dbfs' then 'Zerodbfs' else opcodeName
    fs.readFile fs.normalize(path.join atom.config.get('ide-csound.CSDOCDIR'), filename + '.html'), 'utf8', (error, data) =>
      return if error

      helpElement = new HelpElement
      helpElement.showHelpForOpcode data, opcodeName

      for aElement in helpElement.querySelectorAll('a.link')
        aElement.removeAttribute('title')
        aElement.onclick = =>
          @showHelpForOpcode aElement.textContent

      if @helpPane
        @helpPane.addItem helpElement
        @helpPane.activateItem helpElement
      else
        previousActivePane = atom.workspace.getActivePane()
        @helpPane = atom.workspace.getActivePane().splitRight {items: [helpElement]}
        @subscriptions.add @helpPane.onDidDestroy =>
          @helpPane = undefined
        previousActivePane.activate()

  showHelpForSelectedOpcode: ->
    editor = atom.workspace.getActiveTextEditor()
    editor.selectWordsContainingCursors()
    @showHelpForOpcode editor.getSelectedText()
