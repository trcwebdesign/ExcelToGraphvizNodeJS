Attribute VB_Name = "modCreateGraph"
' Copyright (c) 2015-2022 Jeffrey J. Long. All rights reserved

'@Folder("Relationship Visualizer.Sheets.Data")

Option Explicit

Public Sub AutoDraw()
    If SettingsSheet.Range(SETTINGS_IMAGE_WORKSHEET).Value = "data" And _
        ActiveSheet.name = DataSheet.name And _
        SettingsSheet.Range(SETTINGS_RUN_MODE).Value = TOGGLE_AUTO Then
        
        ' Show the hourglass cursor
        Application.Cursor = xlWait
        
        ' Clear pending events
        DoEvents
    
        OptimizeCode_Begin
        CreateGraphWorksheet
        OptimizeCode_End
         
        ' Reset the cursor back to the default
        Application.Cursor = xlDefault
    End If

End Sub

Public Sub ClearWorksheetGraphs()
    ' Delete pictures from 'data' worksheet
    DeleteAllPictures GetDataWorksheetName()
            
    ' Delete pictures from the 'graph' worksheet
    DeleteAllPictures GraphSheet.name
End Sub

Public Sub ClearErrors()

    ' Data worksheet variables
    Dim data As dataWorksheet
    data = GetSettingsForDataWorksheet(GetDataWorksheetName())
    
    ' Iterate through the rows
    Dim row As Long
    For row = data.firstRow To data.lastRow
        If GetCell(data.worksheetName, row, data.flagColumn) = FLAG_ERROR Then
            ClearCell data.worksheetName, row, data.flagColumn
            ClearCell data.worksheetName, row, data.errorMessageColumn
        End If
    Next row

End Sub


'@ExcelHotkey q
Public Sub CreateGraphWorksheetQuickly()
Attribute CreateGraphWorksheetQuickly.VB_ProcData.VB_Invoke_Func = "q\n14"
    ' Show the hourglass cursor
    Application.Cursor = xlWait
    DoEvents
    
    OptimizeCode_Begin
    CreateGraphWorksheet
    OptimizeCode_End
    
    ' Reset the cursor back to the default
    Application.Cursor = xlDefault
End Sub

'@Ignore MissingMemberAnnotation
Public Sub CreateGraphWorksheet()
Attribute CreateGraphWorksheet.VB_ProcData.VB_Invoke_Func = " \n14"

    On Error Resume Next
    
#If Mac Then
    ' For some reason, my Mac fails when I code it as "#If Not Mac Then"
#Else
    ' Start a timer
    Dim timex As Stopwatch
    Set timex = New Stopwatch
    timex.start
#End If
    
    ' Clear the status bar
    ClearStatusBar

    ' Read in the runtime settings
    Dim ini As settings
    ini = GetSettings(GetDataWorksheetName())

    If Not WorksheetExists(ini.data.worksheetName) Then
        MsgBox GetMessage("msgboxNoDataToGraph"), vbOKOnly, , GetMessage(MSGBOX_PRODUCT_TITLE)
        Exit Sub
    End If

    ' Remove any existing graph image from the target worksheet
    Dim displayDataSheetName As String
    Dim targetCell As String

    If ini.graph.imageWorksheet = "data" Then
        displayDataSheetName = ini.data.worksheetName
        targetCell = ini.data.graphDisplayColumnAsAlpha & ini.data.firstRow
    Else
        displayDataSheetName = GraphSheet.name
        targetCell = "B2"
    End If
            
    ActiveWorkbook.Sheets.[_Default](displayDataSheetName).Activate
    DeleteAllPictures displayDataSheetName

    ' Determine output directory, and build file names
    Dim outputDirectory As String
    outputDirectory = GetTempDirectory()

    Dim filenameBase As String
    Dim graphvizFile As String
    Dim diagramFile As String

    ' Get the file name, minus the file extension
    filenameBase = outputDirectory & Application.pathSeparator & "RelationshipVisualizer"

    ' Add the file extensions
    graphvizFile = filenameBase & GRAPHVIZ_EXTENSION
    diagramFile = filenameBase & "." & ini.graph.imageTypeWorksheet

    ' Create the '.gv' Graphviz source code file from the relationships in the
    ' data worksheet
    If Not GenerateGraphFile(ini, graphvizFile, ini.styles.selectedViewColumn) Then
        ' Report errors to the user
        ShowColumn ini.data.worksheetName, ini.data.errorMessageColumn, True
        Exit Sub
    End If
    
    ' Pull the source code in to enable 'View Source' capapbility if the
    ' source worksheet is not hidden
    If GetSettingBoolean(SETTINGS_TOOLS_TOGGLE_SOURCE) Then
        DisplayFileOnSourceWorksheet graphvizFile
    End If
    
    ' Hide the messages column
    ShowColumn ini.data.worksheetName, ini.data.errorMessageColumn, False

    ' Convert the Graphviz source code into a diagram
    Dim ret As Long
    ret = CreateGraphDiagram(graphvizFile, diagramFile, _
                             ini.graph.imageTypeWorksheet, ini.graph.engine, _
                             ini.commandLine.parameters, CLng(ini.graph.maxSeconds) * 1000)
    ' Show the graph image
    If ret = ShellAndWaitResult.success Then
        '@Ignore VariableNotUsed
        Dim shapeObject As Shape
        Set shapeObject = InsertPicture(diagramFile, ActiveSheet.Range(targetCell), False, True)
        
        ' This is a kludgey way to handle the image scaling because VBA does not have a datatype
        ' for floating point numbers.
        If ini.graph.scaleImage = 75 Then
            ActiveSheet.Pictures(ActiveSheet.Pictures.Count).ShapeRange.ScaleHeight 0.75, msoFalse, msoScaleFromTopLeft
        ElseIf ini.graph.scaleImage = 50 Then
            ActiveSheet.Pictures(ActiveSheet.Pictures.Count).ShapeRange.ScaleHeight 0.5, msoFalse, msoScaleFromTopLeft
        ElseIf ini.graph.scaleImage = 25 Then
            ActiveSheet.Pictures(ActiveSheet.Pictures.Count).ShapeRange.ScaleHeight 0.25, msoFalse, msoScaleFromTopLeft
        Else
            ActiveSheet.Pictures(ActiveSheet.Pictures.Count).ShapeRange.ScaleHeight 1, msoFalse, msoScaleFromTopLeft
        End If
        If ini.graph.pictureName <> vbNullString Then
            ActiveSheet.Pictures(ActiveSheet.Pictures.Count).name = ini.graph.pictureName
        End If
        Set shapeObject = Nothing
    Else                                    ' Report errors to the user
        ShellAndWaitMessage ret
    End If

    ' Delete the temporary files
    DeleteFile graphvizFile
    DeleteFile diagramFile
    
#If Mac Then
    ' For some reason, my Mac fails when I code it as "#If Not Mac Then"
#Else
    ' Stop the timer
    timex.stop_it
    Application.StatusBar = timex.Elapsed_sec & " seconds"
#End If
    
    On Error GoTo 0
End Sub

Public Sub CreateGraphFile(ByVal firstViewColumn As Long, ByVal lastViewColumn As Long)
    Dim viewColumn As Long
    
    Dim filenameBase As String
    Dim graphvizFile As String
    Dim ret As Long
    Dim diagramFile As String
    
    ' Clear the status bar
    ClearStatusBar
    
    ' Read in the runtime settings
    Dim ini As settings
    ini = GetSettings(GetDataWorksheetName())

    If Not WorksheetExists(ini.data.worksheetName) Then
        MsgBox GetMessage("msgboxNoDataToGraph"), vbOKOnly, GetMessage(MSGBOX_PRODUCT_TITLE)
        Exit Sub
    End If

    ' Determine output directory, and build file names
    If ini.output.directory = vbNullString Then
        ini.output.directory = vbNullString = ActiveWorkbook.path
    End If

    ' Hide the messages column
    ShowColumn ini.data.worksheetName, ini.data.errorMessageColumn, False
    
    For viewColumn = firstViewColumn To lastViewColumn
        ' Get the file name, minus the file extension
        filenameBase = GetFilenameBase(ini, viewColumn)

        ' Compose the filename
        If FileLocationProvided(ini) Then
            filenameBase = GetFilenameBase(ini, viewColumn)
        Else
            Exit Sub
        End If

        ' Create the filenames
        graphvizFile = filenameBase & GRAPHVIZ_EXTENSION  ' Input (Graphviz) source code filename
        diagramFile = filenameBase & "." & ini.graph.imageTypeFile ' Output (diagram) filename

#If Mac Then
        ' If we are running on a Mac, and we are not going to keep the source file, use a filename within
        ' the sandbox which the user will not have to grant permission to use. If keeping the file, they
        ' will just have to grant permission.
        
        If ini.graph.fileDisposition = "delete" Then
            graphvizFile = GetTempDirectory() & Application.pathSeparator & "RelationshipVisualizer" & GRAPHVIZ_EXTENSION
        End If
    
#End If
        ' Create Graphviz graph source code
        If Not GenerateGraphFile(ini, graphvizFile, viewColumn) Then
            Exit Sub
        End If
        
        ' Pull the source code in to enable 'View Source' capapbility if the source worksheet is not hidden.
        ' Since we are running in a loop, only show the source code for the last graph generate
        If GetSettingBoolean(SETTINGS_TOOLS_TOGGLE_SOURCE) And (viewColumn = lastViewColumn) Then
            DisplayFileOnSourceWorksheet graphvizFile
        End If
    
        ' Convert source code into a graph diagram
        ret = CreateGraphDiagram(graphvizFile, diagramFile, ini.graph.imageTypeFile, _
                                 ini.graph.engine, ini.commandLine.parameters, CLng(ini.graph.maxSeconds) * 1000)
        
        If ret <> ShellAndWaitResult.success Then    ' Inform user of failure
            ShellAndWaitMessage ret
        End If
        
        ' If the diagram file is not there, then Graphviz failed
        If FileExists(diagramFile) Then
            ' Post-process SVG files to add things like animations
            If ini.graph.imageTypeFile = FILETYPE_SVG And ini.graph.postProcessSVG Then
                FindAndReplaceSVG diagramFile, diagramFile
            End If
            
            UpdateStatusBarForNSeconds GetMessage("statusbarGraphFilenameIs") & " " & diagramFile, 10
        Else
            MsgBox GetMessage("msgboxNoGraphCreated"), vbOKOnly, GetMessage(MSGBOX_PRODUCT_TITLE)
        End If

        ' Delete the command file if disposition is 'delete'
        If ini.graph.fileDisposition = "delete" Then
             DeleteFile graphvizFile
        End If
    Next viewColumn

End Sub

Public Sub CreateGraphSource()

    ' Read in the runtime settings
    Dim ini As settings
    ini = GetSettings(GetDataWorksheetName())

    If Not WorksheetExists(ini.data.worksheetName) Then
        MsgBox GetMessage("msgboxNoDataToGraph"), vbOKOnly, GetMessage(MSGBOX_PRODUCT_TITLE)
        Exit Sub
    End If

    ' Determine output directory, and build file names
    Dim outputDirectory As String
    outputDirectory = GetTempDirectory()

    Dim graphvizFile As String
    graphvizFile = outputDirectory & Application.pathSeparator & "RelationshipVisualizer.gv"

    ' Create the '.gv' Graphviz source code file from the relationships in the
    ' data worksheet
    If Not GenerateGraphFile(ini, graphvizFile, ini.styles.selectedViewColumn) Then
        Exit Sub
    End If

    ' Pull the source code in to enable 'View Source' capapbility
    DisplayFileOnSourceWorksheet graphvizFile
    
    ' Hide the messages column
    ShowColumn ini.data.worksheetName, ini.data.errorMessageColumn, False

    ' Delete the temporary files
    DeleteFile graphvizFile
    
End Sub

Public Function FileLocationProvided(ByRef ini As settings) As Boolean
    FileLocationProvided = True
    
    ' Validate that the output directory exists
    If Not DirectoryExists(ini.output.directory) Then
        MsgBox replace(GetMessage("msgboxDirDoesNotExist"), "{dir}", ini.output.directory), vbCritical, GetMessage(MSGBOX_PRODUCT_TITLE)
        FileLocationProvided = False
    End If

    ' Get the base value of the file name
    If ini.output.fileNamePrefix = vbNullString Then
        MsgBox GetMessage("msgboxPrefixNotSpecified"), vbCritical, GetMessage(MSGBOX_PRODUCT_TITLE)
        FileLocationProvided = False
    End If

End Function

Public Function GetFilenameBase(ByRef ini As settings, ByVal showStyleColumn As Long) As String

    Dim fileBase As String

    ' Build up the file name from the user-specified prefix
    fileBase = ini.output.fileNamePrefix
    
    ' Include Timestamp if desired
    If ini.output.appendTimeStamp Then
        If InStr(fileBase, "%D") Or InStr(fileBase, "%T") Then
            ' Substitute date for %D
            If InStr(fileBase, "%D") Then
                fileBase = replace(fileBase, "%D", ini.output.date)
            End If
            
            ' Substitute time for %D
            If InStr(fileBase, "%T") Then
                fileBase = replace(fileBase, "%T", ini.output.time)
            End If
        Else
            fileBase = fileBase & " " & ini.output.date & " " & ini.output.time
        End If
    End If

    ' Include the view name
    If InStr(fileBase, "%V") Then
        ' Substitute View name for %V
        fileBase = replace(fileBase, "%V", StylesSheet.Cells.Item(ini.styles.headingRow, showStyleColumn).Value)
    Else
        fileBase = fileBase & " " & StylesSheet.Cells.Item(ini.styles.headingRow, showStyleColumn).Value
    End If

    ' Include the worksheet name
    If InStr(fileBase, "%W") Then
        ' Substitute data worksheet name for %W
        fileBase = replace(fileBase, "%W", ini.data.worksheetName)
    End If
    
    ' Include Graphing Options if desired
    If ini.output.appendOptions Then
        If InStr(fileBase, "%E") Or InStr(fileBase, "%S") Then
            ' Substitute Graph engine for %E
            If InStr(fileBase, "%E") Then
                fileBase = replace(fileBase, "%E", SettingsSheet.Range(SETTINGS_GRAPHVIZ_ENGINE).Value)
            End If
        
            ' Substitute Splines engine for %S
            If InStr(fileBase, "%S") Then
                fileBase = replace(fileBase, "%S", ini.graph.splines)
            End If
        Else
            fileBase = fileBase & " [" & SettingsSheet.Range(SETTINGS_GRAPHVIZ_ENGINE).Value
            If ini.graph.splines <> vbNullString Then
                fileBase = fileBase & COMMA & ini.graph.splines
            End If
            fileBase = fileBase & "]"
        End If
    End If

    GetFilenameBase = Trim$(ini.output.directory & Application.pathSeparator & fileBase)

End Function

Public Function GetExcelToGraphvizImageDirectory() As String
    GetExcelToGraphvizImageDirectory = Trim$(Environ$("ExcelToGraphvizImages"))
End Function

Public Function GetImagePath() As String

    Dim imagePath As String
    imagePath = SettingsSheet.Range(SETTINGS_IMAGE_PATH).Value
    
    Dim pathSeparator As String
#If Mac Then
    pathSeparator = COLON
#Else
    pathSeparator = SEMICOLON
#End If

    ' Include current directory on the image path
    If imagePath = vbNullString Then
        imagePath = Application.ActiveWorkbook.path
    Else
        imagePath = Application.ActiveWorkbook.path & pathSeparator & imagePath
    End If

    ' Append the directory associated with the environment variable
    ' to the image path, if a path has been specified
    Dim envImagePath As String
    envImagePath = GetExcelToGraphvizImageDirectory()
    If envImagePath <> vbNullString Then
        imagePath = imagePath & pathSeparator & envImagePath
    End If

    GetImagePath = imagePath
    
End Function

Private Function DetermineStyleName(ByRef ini As settings, ByVal row As Long) As String

    Dim styleName As String
    
    Dim dataItem As String
    dataItem = GetCell(ini.data.worksheetName, row, ini.data.itemColumn)

    If dataItem <> vbNullString Then
        If EndsWith(dataItem, OPEN_BRACE) Then
            styleName = TYPE_SUBGRAPH_OPEN
        
        ElseIf dataItem = CLOSE_BRACE Then
            styleName = TYPE_SUBGRAPH_CLOSE
        
        ElseIf dataItem = GREATER_THAN Then
            styleName = TYPE_NATIVE
        
        Else
            Dim dataIsRelatedtoItem As String
            dataIsRelatedtoItem = GetCell(ini.data.worksheetName, row, ini.data.isRelatedToItemColumn)
            
            If dataIsRelatedtoItem = vbNullString Then
                If dataItem = KEYWORD_NODE Or dataItem = KEYWORD_EDGE Or dataItem = KEYWORD_GRAPH Then
                    styleName = TYPE_KEYWORD
                Else
                    styleName = TYPE_NODE
                End If
            Else
                styleName = TYPE_EDGE
            End If
        End If
    End If

    DetermineStyleName = styleName
    
End Function

Private Function RemovePort(ByVal nodeId As String) As String
    
    ' Strip off the port (if specified)
    If InStr(nodeId, ":") > 0 Then
        RemovePort = GetStringTokenAtPosition(nodeId, ":", 1)
    Else
        RemovePort = nodeId
    End If

End Function

Private Function GenerateGraphFile(ByRef ini As settings, _
                                  ByVal graphvizFilename As String, _
                                  ByVal showStyleColumn As Long) As Boolean

    GenerateGraphFile = True

    ' Dictionaries to determine what data is referenced
    Dim nodeIds As Dictionary
    Set nodeIds = New Dictionary
    
    Dim edgeIds As Dictionary
    Set edgeIds = New Dictionary
    
    Dim nodeIdsInRelationships As Dictionary
    Set nodeIdsInRelationships = New Dictionary

    ' Cache the style definitions in the 'styles' worksheet
    Dim styles As Dictionary
    Set styles = CacheEnabledStyles(ini, showStyleColumn)
    
    ' Remove any error messages from a previous run
    Dim row As Long
    For row = ini.data.firstRow To ini.data.lastRow
        If GetCell(ini.data.worksheetName, row, ini.data.flagColumn) = FLAG_ERROR Then
            ClearCell ini.data.worksheetName, row, ini.data.flagColumn
            ClearCell ini.data.worksheetName, row, ini.data.errorMessageColumn
        End If
    Next row

    ' Inspect the data if we are to filter out orphan types
    If Not ini.graph.includeOrphanNodes Or Not ini.graph.includeOrphanEdges Then
        ' Iterate through the rows to determine what nodes and edges have valid
        ' style definitions, and collect this information in lists.
        ConfirmItemStyleIsValid ini, styles, nodeIds, edgeIds
        
        ' Determine if both the tail and head of the included relationships refer
        ' to nodes which have been included, and have style definitions
        DetermineWhatGraphShouldInclude ini, styles, nodeIds, nodeIdsInRelationships
    End If

    ' Generate the dot language Graphviz file
    Dim errorCount As Long
    errorCount = ValidateData(ini, styles)
                                
    If errorCount = 0 Then
        ' Generate the dot language Graphviz file
        GenerateGraphFile = WriteGraphvizSource(ini, graphvizFilename, styles, nodeIds, nodeIdsInRelationships)
    Else
        ' The file cannot be generated because there are errors in the data
        GenerateGraphFile = False
    End If
    
    ' Clean up so we don't have a memory leak
    Set styles = Nothing
    Set nodeIds = Nothing
    Set edgeIds = Nothing
    Set nodeIdsInRelationships = Nothing
    
End Function

Private Sub ConfirmItemStyleIsValid(ByRef ini As settings, _
                                   ByVal styles As Dictionary, _
                                   ByVal nodeIds As Dictionary, _
                                   ByVal edgeIds As Dictionary)
    Dim row As Long
    Dim data As dataRow
    
    Dim nodeId As String
    Dim itemIdArray() As String
    
    Dim arrayIndex As Long
    
    For row = ini.data.firstRow To ini.data.lastRow
        If GetCell(ini.data.worksheetName, row, ini.data.flagColumn) <> FLAG_COMMENT Then ' line is not commented out
            data.styleName = GetCell(ini.data.worksheetName, row, ini.data.styleNameColumn)

            ' Try to determine the style if not supplied
            If data.styleName = vbNullString Then
                data.styleName = DetermineStyleName(ini, row)
            End If

            ' Get the style names in a consistent case
            data.styleName = UCase$(data.styleName)
            
            If data.styleName <> vbNullString Then ' a style was specified
                If styles.Exists(data.styleName) Then ' show this in the diagram

                    ' We want data of this style in the output file
                    data.Item = GetCell(ini.data.worksheetName, row, ini.data.itemColumn)
                    data.relatedItem = GetCell(ini.data.worksheetName, row, ini.data.isRelatedToItemColumn)
                        
                    ' What type of row is it?
                    data.styleType = styles.Item(data.styleName).styleType

                    If data.styleType = TYPE_NODE Then

                        If data.Item <> vbNullString And UCase$(data.Item) <> KEYWORD_NODE And data.relatedItem = vbNullString Then
                        
                            ' There are potentially multiple item IDs, so parse them from the data.item string
                            itemIdArray = Split(data.Item, COMMA)
                            For arrayIndex = LBound(itemIdArray) To UBound(itemIdArray)
                                nodeId = RemovePort(itemIdArray(arrayIndex))
                                If Not nodeIds.Exists(nodeId) Then
                                    nodeIds.Add nodeId, True
                                End If
                            Next
                        End If

                    ElseIf data.styleType = TYPE_EDGE Then

                        If data.Item <> vbNullString And UCase$(data.Item) <> KEYWORD_EDGE And data.relatedItem <> vbNullString Then
                            ' There are potentially multiple item IDs, so parse them from the data.item string
                            itemIdArray = Split(data.Item, COMMA)
                            For arrayIndex = LBound(itemIdArray) To UBound(itemIdArray)
                                nodeId = RemovePort(itemIdArray(arrayIndex))
                                If Not edgeIds.Exists(nodeId) Then
                                    edgeIds.Add nodeId, True
                                End If
                            Next
                            
                            ' There are potentially multiple related item IDs, so parse them from the data.relatedItem string
                            itemIdArray = Split(data.relatedItem, COMMA)
                            For arrayIndex = LBound(itemIdArray) To UBound(itemIdArray)
                                nodeId = RemovePort(itemIdArray(arrayIndex))

                                If Not edgeIds.Exists(nodeId) Then
                                    edgeIds.Add nodeId, True
                                End If
                            Next
                        End If                   ' if tail and head are non-blank
                    End If                       ' if NODE elseif EDGE
                End If                           ' style is to be included in output diagram
            End If                               ' style was specified
        End If                                   ' not a comment line
    Next row

End Sub

Private Sub DetermineWhatGraphShouldInclude(ByRef ini As settings, _
                                           ByVal styles As Dictionary, _
                                           ByVal nodeIds As Dictionary, _
                                           ByVal nodeIdsInRelationships As Dictionary)
    Dim data As dataRow

    Dim itemID As String
    Dim relatedItemId As String
    
    Dim Items() As String
    Dim itemIndex As Long
    
    Dim relatedItems() As String
    Dim relatedItemIndex As Long
    
    Dim row As Long
    For row = ini.data.firstRow To ini.data.lastRow
        If GetCell(ini.data.worksheetName, row, ini.data.flagColumn) <> FLAG_COMMENT Then ' row is not a comment
            ' Get the style of the item
            data.styleName = GetCell(ini.data.worksheetName, row, ini.data.styleNameColumn)

            ' Try to determine the style if not supplied
            If data.styleName = vbNullString Then
                data.styleName = DetermineStyleName(ini, row)
            End If

            ' Get the style names in a consistent case
            data.styleName = UCase$(data.styleName)
            
            If data.styleName <> vbNullString Then ' this is not a blank line
                If styles.Exists(data.styleName) Then ' this style should be shown in diagram

                    ' We want data of this style in the output file
                    data.Item = GetCell(ini.data.worksheetName, row, ini.data.itemColumn)
                    data.relatedItem = GetCell(ini.data.worksheetName, row, ini.data.isRelatedToItemColumn)

                    If styles.Item(data.styleName).styleType = TYPE_EDGE Then ' this line is a relationship

                        If data.Item <> vbNullString And UCase$(data.Item) <> KEYWORD_EDGE And data.relatedItem <> vbNullString Then ' a tail and head are present

                            Items = Split(data.Item, COMMA)
                            relatedItems = Split(data.relatedItem, COMMA)
                            
                            For itemIndex = LBound(Items) To UBound(Items)
                                For relatedItemIndex = LBound(relatedItems) To UBound(relatedItems)
                                    ' If both the tail and the head in the relationship refer
                                    ' to included nodes having style definitions, track the nodes
                                    ' as "Is Used" so that we later determine island nodes to exclude
                                    ' from the graph.
                                
                                    itemID = RemovePort(Items(itemIndex))
                                    relatedItemId = RemovePort(relatedItems(relatedItemIndex))

                                    If nodeIds.Exists(itemID) And nodeIds.Exists(relatedItemId) Then
                                        If Not nodeIdsInRelationships.Exists(itemID) Then
                                            nodeIdsInRelationships.Add itemID, True
                                        End If
                                
                                        If Not nodeIdsInRelationships.Exists(relatedItemId) Then
                                            nodeIdsInRelationships.Add relatedItemId, True
                                        End If
                                    End If       ' tail and head relate to included nodes
                                Next
                            Next
                        End If                   ' tail and head are non-blank
                    End If                       ' data.styleName = EDGE
                End If                           ' show item = YES
            End If                               ' not a blank line
        End If                                   ' not commented out
    Next row

End Sub

Private Function ValidateData(ByRef ini As settings, ByVal styles As Dictionary) As Long

    Dim data As dataRow
    
    Dim row As Long
    Dim openSubgraphs As Long
    Dim errCnt As Long

    ' Initializations
    openSubgraphs = 0
    errCnt = 0
    
    ' Iterate through the rows of data
    For row = ini.data.firstRow To ini.data.lastRow

        data = GetDataRow(ini, ini.data.worksheetName, row)

        If data.comment <> FLAG_COMMENT Then   ' Don't process the row if it has been commented out
            ' Try to determine the style if not supplied
            If data.styleName = vbNullString Then
                data.styleName = DetermineStyleName(ini, row)
            End If

            ' Get the style names in a consistent case
            data.styleName = UCase$(data.styleName)
            
            ' See if the row has data
            If data.styleName <> vbNullString Then
                ' Determine if this item should be shown in the diagram
                If styles.Exists(data.styleName) Then ' We want data of this style in the output file
                    
                    ' Look up processing attributes from cached stylesheet information
                    data.styleType = styles.Item(data.styleName).styleType
                    
                    ' Validate the rows according to object type
                    If data.styleType = TYPE_NODE Then
                        If data.Item = vbNullString Then
                            LogError ini, row, GetMessage("errormsgNodeNoItemFound"), errCnt
                        
                        ElseIf data.relatedItem <> vbNullString Then
                            LogError ini, row, GetMessage("errormsgImpliedEdgeType"), errCnt
                        End If
                       
                    ElseIf data.styleType = TYPE_EDGE Then
                        '@Ignore EmptyIfBlock
                        If UCase$(data.Item) = KEYWORD_EDGE Then
                            ' No error
                        ElseIf data.Item = vbNullString Then
                            LogError ini, row, GetMessage("errormsgEdgeNoItemFound"), errCnt
                        
                        ElseIf data.relatedItem = vbNullString Then
                            LogError ini, row, GetMessage("errormsgEdgeNoRelatedItemFound"), errCnt
                        End If
                        
                    ElseIf data.styleType = TYPE_SUBGRAPH_OPEN Then
                        openSubgraphs = openSubgraphs + 1
                                                
                    ElseIf data.styleType = TYPE_SUBGRAPH_CLOSE Then
                        openSubgraphs = openSubgraphs - 1
    
                        If openSubgraphs < 0 Then
                            LogError ini, row, GetMessage("errormsgBracesExcessClose"), errCnt
                        End If
                    End If
                End If
            End If
        End If
    Next row

    ' Alert the user if it appears that the subgraphs open and close braces are out of balance
    If openSubgraphs > 0 Then
        LogError ini, row, replace(GetMessage("errormsgBracesExcessOpen"), "{openSubgraphs}", openSubgraphs), errCnt
    End If

    ' Return count of errors encountered
    ValidateData = errCnt
    
End Function

Private Function isKeyword(ByVal Item As String) As Boolean
    isKeyword = (UCase$(Item) = KEYWORD_NODE) Or (UCase$(Item) = KEYWORD_EDGE) Or (UCase$(Item) = KEYWORD_GRAPH)
End Function

Private Function WriteGraphvizSource(ByRef ini As settings, _
                                    ByVal graphvizFile As String, _
                                    ByVal styles As Dictionary, _
                                    ByVal nodeIds As Dictionary, _
                                    ByVal relationshipIds As Dictionary) As Boolean
    WriteGraphvizSource = True

    ' Subgraph cluster counter
    Dim clusterCnt As Long
    clusterCnt = 0
    
    ' Trap any file system I/O-related errors
    On Error GoTo EndMacro:
    
    ' Create output file objects
    Dim textStream As String
    
    ' Set the  Graphviz 'strict' directive
    Dim graphStrict As String
    If ini.graph.addStrict Then
        graphStrict = "strict"
    End If
    
    ' Create the first lines of the dot graph program
    textStream = textStream & Trim$(graphStrict & " " & ini.graph.command & " " & AddQuotes("main")) & vbNewLine
    textStream = textStream & OPEN_BRACE & vbNewLine
    
    ' Establish source indentation
    Dim indent As Long
    indent = IncreaseIndent(0)
    
    ' Write out the graph directives before processing the rows of data
    ProcessGraphOptions textStream, ini, indent
    
    ' Iterate through the rows of data
    Dim row As Long
    Dim data As dataRow
    For row = ini.data.firstRow To ini.data.lastRow

        data = GetDataRow(ini, ini.data.worksheetName, row)

        ' Don't process the row if it has been commented out
        If data.comment <> FLAG_COMMENT Then
        
            ' Try to determine the style if not supplied
            If data.styleName = vbNullString Then
                data.styleName = DetermineStyleName(ini, row)
            End If

            ' Treat all style names as uppercase for consistency
            data.styleName = UCase$(data.styleName)
            
            ' See if the row has data
            '@Ignore EmptyIfBlock
            If data.styleName = vbNullString Then
                ' No style was specified, assume the row is blank and skip it.
            Else
                ' Determine if this item should be shown in the diagram
                Dim showStyle As Boolean
                showStyle = styles.Exists(data.styleName)
                
                Dim boolKeyword As Boolean
                boolKeyword = isKeyword(data.Item)
                
                If showStyle Or boolKeyword Then ' We want data of this style in the output file
                    
                    ' Look up processing attributes from cached stylesheet information
                    data.styleType = styles.Item(data.styleName).styleType
                    
                    If ini.graph.includeStyleFormat And showStyle Then
                        data.format = styles.Item(data.styleName).styleFormat
                    Else
                        data.format = vbNullString
                    End If
                    
                    ' Append information to the label if debugging is enabled
                    If ini.graph.debug Then
                        data.label = FormatDebugLabel(row, data)
                        data.xLabel = FormatDebugXLabel(row, data)
                    End If

                    ' Process the rows according to object type
                    If boolKeyword Then
                        textStream = textStream & ProcessKeyword(ini, data, indent)

                    ElseIf data.styleType = TYPE_NODE Then
                        textStream = textStream & ProcessNode(ini, data, indent, relationshipIds)

                    ElseIf data.styleType = TYPE_EDGE Then
                        textStream = textStream & ProcessEdge(ini, data, indent, nodeIds)

                    ElseIf data.styleType = TYPE_SUBGRAPH_OPEN Then
                        textStream = textStream & ProcessSubgraphOpen(ini, data, indent, clusterCnt)
                        indent = IncreaseIndent(indent)
                        
                    ElseIf data.styleType = TYPE_SUBGRAPH_CLOSE Then
                        indent = DecreaseIndent(indent)
                        textStream = textStream & ProcessSubgraphClose(ini, data, indent)

                    ElseIf data.styleType = TYPE_KEYWORD Then
                        textStream = textStream & ProcessKeyword(ini, data, indent)

                    ElseIf data.styleType = TYPE_NATIVE Then
                        textStream = textStream & ProcessNative(ini, data, indent)

                    '@Ignore EmptyElseBlock
                    Else
                        ' Not recognized, ignore it
                    End If
                End If
            End If
        End If
    Next row

    ' Write the last dot statement to terminate the dot source file
    indent = DecreaseIndent(indent)
    textStream = textStream & Space(indent * ini.source.indent) & CLOSE_BRACE & vbNewLine

   ' Write the Graphviz data to a file so it can be sent to a rendering engine
#If Mac Then
    WriteTextToFile textStream, graphvizFile
#Else
    WriteTextToUTF8FileFileWithoutBOM textStream, graphvizFile
#End If

EndMacro:

    If Err.number > 0 Then
        MsgBox "WriteGraphvizSource() - " & Err.number & " " & Err.Description, vbOKOnly, GetMessage(MSGBOX_PRODUCT_TITLE)
        Err.Clear
        WriteGraphvizSource = False
    End If
    
    On Error GoTo 0

End Function

Private Sub ProcessGraphOptions(ByRef textStream As String, ByRef ini As settings, ByVal indent As Long)

    Dim spaces As String
    
    ' Create the indentation string
    spaces = Space(indent * ini.source.indent)
    
    ' Latest Windows version requires you to use DOT.EXE with layout specified as a graph option.
    AddAttributeLine textStream, spaces, "layout", ini.graph.layout
    
    ' Specify how the edges should be drawn and include as the "spline" parameter
    If Trim$(ini.graph.splines) <> vbNullString Then
        AddAttributeLine textStream, spaces, "splines", ini.graph.splines
    End If
    
    ' Make the background transparent if desired
    If ini.graph.transparentBackground Then
        AddAttributeLine textStream, spaces, "bgcolor", "transparent"
    End If
    
    If ini.graph.center Then
        AddAttributeLine textStream, spaces, "center", "true"
    End If
       
    If ini.graph.concentrate Then
        AddAttributeLine textStream, spaces, "concentrate", "true"
    End If
    
    If ini.graph.forceLabels Then
        AddAttributeLine textStream, spaces, "forcelabels", "true"
    End If
    
    ' Specify the directory path where images are located
    If ini.graph.imagePath <> vbNullString Then
        AddAttributeLine textStream, spaces, "imagepath", ini.graph.imagePath
    End If

    ' Process the graph options which are specific to layout engines
    Select Case ini.graph.layout
        Case LAYOUT_CIRCO
            If ini.graph.overlap <> vbNullString Then
                AddAttributeLine textStream, spaces, "overlap", ini.graph.overlap
            End If

            If Trim$(ini.graph.outputOrder) <> vbNullString Then
                AddAttributeLine textStream, spaces, "outputorder", ini.graph.outputOrder
            End If
            
        Case LAYOUT_DOT
            If ini.graph.rankdir <> vbNullString Then
                AddAttributeLine textStream, spaces, "rankdir", ini.graph.rankdir
            End If

            If ini.graph.clusterrank <> vbNullString Then
                AddAttributeLine textStream, spaces, "clusterrank", ini.graph.clusterrank
            End If

            If ini.graph.compound Then
                AddAttributeLine textStream, spaces, "compound", "true"
            End If

            If ini.graph.ordering <> vbNullString Then
                AddAttributeLine textStream, spaces, "ordering", ini.graph.ordering
            End If

            If ini.graph.newrank Then
                AddAttributeLine textStream, spaces, "newrank", "true"
            End If
    
            If Trim$(ini.graph.outputOrder) <> vbNullString Then
                AddAttributeLine textStream, spaces, "outputorder", ini.graph.outputOrder
            End If
            
        Case LAYOUT_FDP
            If ini.graph.layoutDim <> vbNullString Then
                AddAttributeLine textStream, spaces, "dim", ini.graph.layoutDim
            End If

            If ini.graph.layoutDimen <> vbNullString Then
                AddAttributeLine textStream, spaces, "dimen", ini.graph.layoutDimen
            End If

            If ini.graph.overlap <> vbNullString Then
                AddAttributeLine textStream, spaces, "overlap", ini.graph.overlap
            End If

            If Trim$(ini.graph.outputOrder) <> vbNullString Then
                AddAttributeLine textStream, spaces, "outputorder", ini.graph.outputOrder
            End If
            
        Case LAYOUT_NEATO
            If ini.graph.layoutDim <> vbNullString Then
                AddAttributeLine textStream, spaces, "dim", ini.graph.layoutDim
            End If

            If ini.graph.layoutDimen <> vbNullString Then
                AddAttributeLine textStream, spaces, "dimen", ini.graph.layoutDimen
            End If
            
            If ini.graph.overlap <> vbNullString Then
                AddAttributeLine textStream, spaces, "overlap", ini.graph.overlap
            End If

            If ini.graph.mode <> vbNullString Then
                AddAttributeLine textStream, spaces, "mode", ini.graph.mode
            End If

            If ini.graph.model <> vbNullString Then
                AddAttributeLine textStream, spaces, "model", ini.graph.model
            End If

            If Trim$(ini.graph.outputOrder) <> vbNullString Then
                AddAttributeLine textStream, spaces, "outputorder", ini.graph.outputOrder
            End If
            
        Case LAYOUT_OSAGE
            If Trim$(ini.graph.outputOrder) <> vbNullString Then
                AddAttributeLine textStream, spaces, "outputorder", ini.graph.outputOrder
            End If
            
        Case LAYOUT_SFDP
            If ini.graph.layoutDim <> vbNullString Then
                AddAttributeLine textStream, spaces, "dim", ini.graph.layoutDim
            End If

            If ini.graph.layoutDimen <> vbNullString Then
                AddAttributeLine textStream, spaces, "dimen", ini.graph.layoutDimen
            End If
            
            If ini.graph.mode <> vbNullString Then
                AddAttributeLine textStream, spaces, "mode", ini.graph.mode
            End If

            If ini.graph.overlap <> vbNullString Then
                AddAttributeLine textStream, spaces, "overlap", ini.graph.overlap
            End If

            If ini.graph.smoothing <> vbNullString Then
                AddAttributeLine textStream, spaces, "smoothing", ini.graph.smoothing
            End If

            If Trim$(ini.graph.outputOrder) <> vbNullString Then
                AddAttributeLine textStream, spaces, "outputorder", ini.graph.outputOrder
            End If
            
        Case LAYOUT_TWOPI
            If ini.graph.overlap <> vbNullString Then
                AddAttributeLine textStream, spaces, "overlap", ini.graph.overlap
            End If
            
            If Trim$(ini.graph.outputOrder) <> vbNullString Then
                AddAttributeLine textStream, spaces, "outputorder", ini.graph.outputOrder
            End If
            
        Case Else
    End Select

    If ini.graph.orientation Then
        AddAttributeLine textStream, spaces, "rotate", "90"
    End If
    
    ' Graph options from the settings worksheet come last to give the ability to override anything above
    textStream = textStream & spaces & Trim$(ini.graph.options) & vbNewLine
End Sub
Private Sub AddAttributeLine(ByRef textStream As String, ByVal spaces As String, ByVal attributeName As String, ByVal attributeValue As String)
    textStream = textStream & spaces & Trim$(attributeName) & "=" & AddQuotes(attributeValue) & SEMICOLON & vbNewLine
End Sub

Private Function IncreaseIndent(ByVal indent As Long) As Long
    IncreaseIndent = indent + 1
End Function

Private Function DecreaseIndent(ByVal indent As Long) As Long
    DecreaseIndent = indent - 1
    If DecreaseIndent < 0 Then
        DecreaseIndent = 0
    End If
End Function

Public Function GetDataRow(ByRef ini As settings, ByVal worksheetName As String, ByVal row As Long) As dataRow

    GetDataRow.comment = GetCell(worksheetName, row, ini.data.flagColumn)
    GetDataRow.Item = GetCell(worksheetName, row, ini.data.itemColumn)
    GetDataRow.label = GetCell(worksheetName, row, ini.data.labelColumn)
    GetDataRow.xLabel = GetCell(worksheetName, row, ini.data.xLabelColumn)
    GetDataRow.tailLabel = GetCell(worksheetName, row, ini.data.tailLabelColumn)
    GetDataRow.headLabel = GetCell(worksheetName, row, ini.data.headLabelColumn)
    GetDataRow.tooltip = GetCell(worksheetName, row, ini.data.tooltipColumn)
    GetDataRow.relatedItem = GetCell(worksheetName, row, ini.data.isRelatedToItemColumn)
    GetDataRow.styleName = GetCell(worksheetName, row, ini.data.styleNameColumn)
    GetDataRow.extraAttrs = GetCell(worksheetName, row, ini.data.extraAttributesColumn)
    GetDataRow.errorMessage = GetCell(worksheetName, row, ini.data.errorMessageColumn)

End Function


Private Function CacheEnabledStyles(ByRef ini As settings, ByVal showStyleColumn As Long) As Dictionary

    ' Dictionary to hold the key and associated values
    Dim dictionaryObj As Dictionary
    Set dictionaryObj = New Dictionary
    
    ' Loop through the specified range
    Dim row As Long
    Dim styleName As String
    
    For row = ini.styles.firstRow To ini.styles.lastRow
        '@Ignore EmptyIfBlock
        If StylesSheet.Cells.Item(row, ini.styles.flagColumn).Value = FLAG_COMMENT Then
            ' Comment row, ignore it
        ElseIf StylesSheet.Cells.Item(row, showStyleColumn).Value = TOGGLE_YES Then
            ' Retrieve the style name
            styleName = UCase$(StylesSheet.Cells.Item(row, ini.styles.nameColumn).Value)

            If styleName <> vbNullString Then    ' a style name is present
                If Not dictionaryObj.Exists(styleName) Then ' ignore duplicate style names
                    Set dictionaryObj.Item(styleName) = GetStyle(StylesSheet.Cells.Item(row, ini.styles.typeColumn), _
                                                              StylesSheet.Cells.Item(row, ini.styles.formatColumn))
                End If
            End If
        End If
    Next row

    Set CacheEnabledStyles = dictionaryObj
    
End Function

Public Function GetStyle(ByVal styleType As String, ByVal styleFormat As String) As style

    Dim Value As style
    Set Value = New style
        
    Value.styleType = styleType
    Value.styleFormat = styleFormat
    
    Set GetStyle = Value

End Function

Private Sub LogError(ByRef ini As settings, ByVal row As Long, ByVal errorMessage As String, ByRef errCnt As Long)

    SetCell ini.data.worksheetName, row, ini.data.flagColumn, FLAG_ERROR
    SetCell ini.data.worksheetName, row, ini.data.errorMessageColumn, errorMessage

    errCnt = errCnt + 1
    
End Sub

Private Function FormatId(ByVal nodeId As String, ByVal includePorts As Boolean) As String

    Dim formattedId As String
    
    ' Build the id, taking ports into consideration
    If InStr(nodeId, ":") > 0 Then  ' nodeId specifies a port.
        If includePorts Then        ' wrap both sides of the id in quotes
            formattedId = AddQuotes(GetStringTokenAtPosition(nodeId, ":", 1)) & ":" & AddQuotes(GetStringTokenAtPosition(nodeId, ":", 2))
        Else    ' strip the port off
            formattedId = AddQuotes(GetStringTokenAtPosition(nodeId, ":", 1))
        End If
    Else        ' no port was specified
        formattedId = AddQuotes(nodeId)
    End If

    FormatId = formattedId
    
End Function

Private Function FormatDebugLabel(ByVal row As Long, ByRef data As dataRow) As String
                        
    Dim debugStr As String

    FormatDebugLabel = data.label
    
    If Not IsLabelHTMLLike(data.label) Then
        If data.styleType = TYPE_EDGE Then
            debugStr = "(Row: " & row & " " & FormatId(data.Item, True) & "->" & FormatId(data.relatedItem, True) & ")"
                        
            If data.label = vbNullString Then
                FormatDebugLabel = debugStr
            Else
                FormatDebugLabel = data.label & NEWLINE & debugStr
            End If
                        
        ElseIf data.styleType = TYPE_NODE Then
            debugStr = "(Row: " & row & " " & AddQuotes(data.Item) & ")"
                            
            If data.label = vbNullString Then
                FormatDebugLabel = debugStr
            Else
                FormatDebugLabel = data.label & NEWLINE & debugStr
            End If
                        
        ElseIf data.styleType = TYPE_SUBGRAPH_OPEN Then
            debugStr = "(Row: " & row & ")"
                            
            If data.label = vbNullString Then
                FormatDebugLabel = debugStr
            Else
                FormatDebugLabel = data.label & NEWLINE & debugStr
            End If
        End If
    End If
    
End Function

Private Function FormatDebugXLabel(ByVal row As Long, ByRef data As dataRow) As String
                        
    Dim debugStr As String

    FormatDebugXLabel = data.xLabel

    If Not IsLabelHTMLLike(data.label) Then
        If data.styleType = TYPE_EDGE Then
            debugStr = "(Row: " & row & " " & AddQuotes(data.Item) & "->" & AddQuotes(data.relatedItem) & ")"
            
            If data.xLabel <> vbNullString Then
                FormatDebugXLabel = data.xLabel & NEWLINE & debugStr
            End If
            
        ElseIf data.styleType = TYPE_NODE Then
            debugStr = "(Row: " & row & " " & AddQuotes(data.Item) & ")"
                            
            If data.xLabel <> vbNullString Then
                FormatDebugXLabel = data.xLabel & NEWLINE & debugStr
            End If
        End If
    End If
    
End Function

Private Function FormatEdgeLabels(ByRef ini As settings, ByRef data As dataRow) As String

    Dim edgeLabel As String
    
    If ini.graph.includeEdgeLabels Then
        If data.label = vbNullString Then
            If ini.graph.blankEdgeLabels Then
                ' True, label = edge id
                edgeLabel = " label=" & AddQuotes("\E")
            End If
        Else
            edgeLabel = " label=" & FormatLabel(data.label)
        End If
    End If

    If ini.graph.includeEdgeXLabels And data.xLabel <> vbNullString Then
        edgeLabel = edgeLabel & " xlabel=" & FormatLabel(data.xLabel)
    End If
            
    If ini.graph.includeEdgeTailLabels And data.tailLabel <> vbNullString Then
        edgeLabel = edgeLabel & " taillabel=" & FormatLabel(data.tailLabel)
    End If
            
    If ini.graph.includeEdgeHeadLabels And data.headLabel <> vbNullString Then
        edgeLabel = edgeLabel & " headlabel=" & FormatLabel(data.headLabel)
    End If
    
    FormatEdgeLabels = edgeLabel
    
End Function

Private Function FormatNodeLabels(ByRef ini As settings, ByRef data As dataRow) As String

    Dim nodeLabel As String
   
    If ini.graph.includeNodeLabels Then
        If data.label = vbNullString Then
            If ini.graph.blankNodeLabels Then    ' True = use default Graphviz behavior.
                nodeLabel = vbNullString
            Else                                 ' False, send null value as the label
                nodeLabel = " label=" & FormatLabel(vbNullString)
            End If
        Else
            nodeLabel = " label=" & FormatLabel(data.label)
        End If
    End If

    If ini.graph.includeNodeXLabels And data.xLabel <> vbNullString Then
        nodeLabel = nodeLabel & " xlabel=" & FormatLabel(data.xLabel)
    End If

    FormatNodeLabels = nodeLabel
    
End Function

Private Function ProcessSubgraphOpen(ByRef ini As settings, ByRef data As dataRow, ByVal indent As Long, ByRef clusterCnt As Long) As String

    Dim subgraphName As String
    subgraphName = Trim$(GetStringBetweenDelimiters(data.Item, vbNullString, OPEN_BRACE))
                        
    If subgraphName = vbNullString Then          ' No subgraph name supplied
        ' Increment the cluster counter, and use it in the cluster name
        clusterCnt = clusterCnt + 1
        subgraphName = "cluster_" & clusterCnt
    End If

    Dim subgraphDirective As String
    subgraphDirective = Space(indent * ini.source.indent) & "subgraph " & AddQuotes(subgraphName) & " {" & " " & Trim$(data.format)

    ' Inclduing the extra style attributes can be turned on/off in the settings
    If data.extraAttrs <> vbNullString Then
        If ini.graph.includeExtraAttributes Then
            subgraphDirective = subgraphDirective & " " & data.extraAttrs
        End If
    End If

    ' The subgraph can have an optional label. Include it if specified
    If data.label <> vbNullString Then
        subgraphDirective = subgraphDirective & " label=" & FormatLabel(data.label)
    End If
                            
    ' If output format is SVG, then include the tooltip data
    Dim tooltip As String
    If ini.graph.includeTooltip Then
        If data.tooltip <> vbNullString Then
            tooltip = " tooltip=" & AddQuotes(ScrubText(data.tooltip))
        End If
    End If
    
    ProcessSubgraphOpen = subgraphDirective & tooltip & vbNewLine

End Function

Private Function ProcessNode(ByRef ini As settings, ByRef data As dataRow, ByVal indent As Long, ByVal nodesUsedInRelationships As Dictionary) As String
                        
    Dim Item As String
    Dim Items() As String
    
    Dim textStream As String
    
    Dim arrayIndex As Long
    
    Item = data.Item
    Items = Split(Item, COMMA)
    
    For arrayIndex = LBound(Items) To UBound(Items)
        data.Item = Trim$(Items(arrayIndex))
                        
        ' Filter out nodes without node relationships
        If Not ini.graph.includeOrphanNodes Then
            If nodesUsedInRelationships.Exists(RemovePort(data.Item)) Then
                textStream = textStream & WriteNode(ini, data, indent)
            End If
        Else
            textStream = textStream & WriteNode(ini, data, indent)
        End If
    Next

    ProcessNode = textStream
End Function

Private Function ProcessEdge(ByRef ini As settings, ByRef data As dataRow, ByVal indent As Long, ByVal definedNodes As Dictionary) As String
                        
    Dim Item As String
    Dim relatedItem As String
    Dim Items() As String
    Dim relatedItems() As String
    
    Dim textStream As String
    
    Dim itemIndex As Long
    Dim relatedItemIndex As Long
    
    Item = data.Item
    Items = Split(Item, COMMA)
    
    relatedItem = data.relatedItem
    relatedItems = Split(relatedItem, COMMA)
    
    For itemIndex = LBound(Items) To UBound(Items)
        For relatedItemIndex = LBound(relatedItems) To UBound(relatedItems)
            data.Item = Trim$(Items(itemIndex))
            data.relatedItem = Trim$(relatedItems(relatedItemIndex))
            
            ' Filter out relationships without node definitions
            If Not ini.graph.includeOrphanEdges Then
                If definedNodes.Exists(RemovePort(data.Item)) And definedNodes.Exists(RemovePort(data.relatedItem)) Then
                    textStream = textStream & WriteEdge(ini, data, indent)
                End If
            Else
                textStream = textStream & WriteEdge(ini, data, indent)
            End If
        Next
    Next

    ProcessEdge = textStream
End Function

Private Function ProcessSubgraphClose(ByRef ini As settings, ByRef data As dataRow, ByVal indent As Long) As String
    ProcessSubgraphClose = Space(indent * ini.source.indent) & data.Item & vbNewLine
End Function

Private Function WriteNode(ByRef ini As settings, ByRef data As dataRow, ByVal indent As Long) As String

    Dim nodeLabel As String
    Dim styleAttributes As String
    
    Dim nodeId As String
    nodeId = data.Item
    
    ' Strip off the port (if specified)
    If InStr(nodeId, ":") > 0 Then
        nodeId = GetStringTokenAtPosition(nodeId, ":", 1)
    End If

    ' If output format is SVG, then include the tooltip data
    Dim tooltip As String
    If ini.graph.includeTooltip Then
        If data.tooltip <> vbNullString Then
            tooltip = " tooltip=" & AddQuotes(ScrubText(data.tooltip))
        End If
    End If
    
    styleAttributes = Trim$(data.format)

    ' Include the extra style attributes if enabled in the settings
    If ini.graph.includeExtraAttributes Then
        styleAttributes = Trim$(styleAttributes & " " & data.extraAttrs)
    End If

    ' If no style has been specified, assume the user wants the shape to be what the
    ' HTML will render. For this situation Graphviz has to be told the shape is "plaintext"
    If (IsLabelHTMLLike(data.label)) And styleAttributes = vbNullString Then
        styleAttributes = "shape=" & AddQuotes("plaintext") & " "
    End If

    ' Collect the label, and xlabel labels into name value pairs
    nodeLabel = FormatNodeLabels(ini, data)
    
    If Trim$(styleAttributes & nodeLabel & tooltip) = vbNullString Then
        WriteNode = Space(indent * ini.source.indent) & AddQuotes(nodeId) & SEMICOLON & vbNewLine
    Else
        WriteNode = Space(indent * ini.source.indent) & AddQuotes(nodeId) & "[ " & Trim$(styleAttributes & nodeLabel) & tooltip & " ];" & vbNewLine
    End If

End Function

Private Function WriteEdge(ByRef ini As settings, ByRef data As dataRow, ByVal indent As Long) As String

    Dim styleAttributes As String
    styleAttributes = data.format

    ' Include the extra style attributes if enabled in the settings
    If ini.graph.includeExtraAttributes Then
        styleAttributes = styleAttributes & " " & data.extraAttrs
    End If

    ' If output format is SVG, then include the tooltip data
    Dim tooltip As String
    If ini.graph.includeTooltip Then
        If data.tooltip <> vbNullString Then
            tooltip = " tooltip=" & AddQuotes(ScrubText(data.tooltip))
        End If
    End If
    
    styleAttributes = Trim$(styleAttributes)
    
    ' Collect the label, xlabel, taillabel, and headlabel labels into name value pairs
    Dim edgeLabel As String
    edgeLabel = FormatEdgeLabels(ini, data)

    ' Add the quotes to the id and (optional) port for the item, and the "is related to" item
    Dim tailId As String
    tailId = FormatId(data.Item, ini.graph.includeEdgePorts)
    
    Dim headId As String
    headId = FormatId(data.relatedItem, ini.graph.includeEdgePorts)
    
    ' Write out the edge command
    If Trim$(styleAttributes & edgeLabel & tooltip) = vbNullString Then
        WriteEdge = Space(indent * ini.source.indent) & tailId & " " & ini.graph.edgeOperator & " " & headId & SEMICOLON & vbNewLine
    Else
        WriteEdge = Space(indent * ini.source.indent) & tailId & " " & ini.graph.edgeOperator & " " & headId & "[ " & Trim$(styleAttributes & edgeLabel) & tooltip & " ];" & vbNewLine
    End If
    
End Function

Private Function ProcessNative(ByRef ini As settings, ByRef data As dataRow, ByVal indent As Long) As String
    ProcessNative = Space(indent * ini.source.indent) & data.label & vbNewLine
End Function

Private Function ProcessKeyword(ByRef ini As settings, ByRef data As dataRow, ByVal indent As Long) As String

    Dim styleAttributes As String
    styleAttributes = Trim$(data.format)

    If ini.graph.includeExtraAttributes Then
        styleAttributes = Trim$(styleAttributes & " " & data.extraAttrs)
    End If

    Dim labelValue As String
    If UCase$(data.Item) = KEYWORD_NODE Then
        labelValue = FormatNodeLabels(ini, data)
    
    ElseIf UCase$(data.Item) = KEYWORD_EDGE Then
        labelValue = FormatEdgeLabels(ini, data)
    
    ElseIf UCase$(data.Item) = KEYWORD_GRAPH Then
        If data.label <> vbNullString Then
            labelValue = labelValue & " label=" & FormatLabel(data.label)
        End If
    End If
        
    ProcessKeyword = Space(indent * ini.source.indent) & data.Item & "[ " & Trim$(styleAttributes & labelValue) & " ];" & vbNewLine
    
End Function

Private Function FormatLabel(ByVal labelValue As String) As String

    If IsLabelHTMLLike(labelValue) Then          ' just return it intact
        FormatLabel = labelValue
    Else
        FormatLabel = AddQuotes(ScrubText(labelValue))
    End If

End Function

Private Function ScrubText(ByVal rawData As String) As String
    If rawData = Chr$(34) & Chr$(34) Then
        ScrubText = vbNullString                 ' "" to blank a label
    Else
        ScrubText = replace(rawData, Chr$(10), NEWLINE) ' Chr(10) 0x0a LF  Line Feed
        ScrubText = replace(ScrubText, "\" & Chr$(34), Chr$(34)) ' In case they already escaped the double quote
        ScrubText = replace(ScrubText, Chr$(34), "\" & Chr$(34)) ' Chr(34)      " Double quotes (or speech marks)
    End If
End Function

Public Function IsLabelHTMLLike(ByVal label As String) As Boolean

    IsLabelHTMLLike = False
    
    ' Remove newline characters to create a single line
    Dim singleLineLabel As String
    singleLineLabel = replace(label, Chr$(10), vbNullString)

    ' HTML-like labels have to be wrapped in '<' and '>' characters
    ' Use process of elimination instead of 'and' conditions to improve performance
    If StartsWith(singleLineLabel, LESS_THAN) Then
        If EndsWith(singleLineLabel, GREATER_THAN) Then   ' Label is wrapped in '<' and '>'
        
            ' Interrogate the string between the HTML-like indicators to see if
            ' it is also wrapped in '<' and '>' characters as HTML elements will begin and
            ' end with these characters. This is not a fool-proof determination that
            ' the label text contains valid HTML elements, but it is a fast assessment.
            ' If the HTML is not valid it will show up in the diagram, and the user can
            ' correct their label data.
            
            ' Pluck the label out from between the '<' and '>' characters
            singleLineLabel = Trim$(GetStringBetweenDelimiters(singleLineLabel, LESS_THAN, GREATER_THAN))
            If StartsWith(singleLineLabel, LESS_THAN) Then ' Looks like an HTML open element could be present
                If EndsWith(singleLineLabel, GREATER_THAN) Then ' Looks like an HTML close element could be present.
        
                    If (InStr(singleLineLabel, "</") > 0) Or (InStr(singleLineLabel, "/>") > 0) Then ' At least one HTML close element is present.
                        IsLabelHTMLLike = True   ' label likely contains HTML-like content
                    End If
                End If
            End If
        End If
    End If
    
End Function

Public Function GetDataWorksheetName() As String

    Dim worksheetName As String
    worksheetName = ActiveSheet.name
    
    ' Worksheets which are not allowed to hold graph data
    If worksheetName = DataSheet.name _
       Or worksheetName = GraphSheet.name _
       Or worksheetName = StylesSheet.name _
       Or worksheetName = StyleDesignerSheet.name _
       Or worksheetName = SettingsSheet.name _
       Or worksheetName = HelpShapesSheet.name _
       Or worksheetName = HelpColorsSheet.name _
       Or worksheetName = HelpAttributesSheet.name _
       Or worksheetName = AboutSheet.name _
       Or worksheetName = SourceSheet.name _
       Or worksheetName = SqlSheet.name _
       Or worksheetName = ChoicesSheet.name _
       Or worksheetName = ListsSheet.name _
    Then
        worksheetName = DataSheet.name
    Else
        ' Ensure the worksheet has the same layout of the 'data' worksheet by comparing a few of the key headings
        Dim data As dataWorksheet
        data = GetSettingsForDataWorksheet(worksheetName)

        If GetCell(worksheetName, data.headingRow, data.itemColumn) <> DataSheet.Cells.Item(data.headingRow, data.itemColumn).Value Then
            worksheetName = DataSheet.name
        ElseIf GetCell(worksheetName, data.headingRow, data.labelColumn) <> DataSheet.Cells.Item(data.headingRow, data.labelColumn).Value Then
            worksheetName = DataSheet.name
        ElseIf GetCell(worksheetName, data.headingRow, data.isRelatedToItemColumn) <> DataSheet.Cells.Item(data.headingRow, data.isRelatedToItemColumn).Value Then
            worksheetName = DataSheet.name
        End If
    End If
    
    GetDataWorksheetName = worksheetName
End Function
