' Copyright (c) 2019 true[X], Inc. All rights reserved.
'----------------------------------------------------------------------------------------------
' MainScene
'----------------------------------------------------------------------------------------------
' Drives UX by coordinating Flow's.
'
' Member Variables:
'   * tarLibrary as ComponentLibrary - used to track the True[X] Component library load status
'   * rootLayout as Node - used as the parent layout for Flow's
'----------------------------------------------------------------------------------------------

'------------------------------------------------------------------------------------------------------
' Begins True[X] ComponentLibrary loading process, ensures global fields are initialized, and presents
' the LoadingFlow to indicate that a (potentially) long running operation is being performed.
'------------------------------------------------------------------------------------------------------
sub init()
    trace("init()")

    ' grab a reference to the root layout node, which will be the parent layout for all nodes
    m.rootLayout = m.top.findNode("rootLayout")

    ' listen for Truex library load events
    m.tarLibrary = m.top.findNode("TruexAdRendererLib")
    m.tarLibrary.observeField("loadStatus", "onTruexLibraryLoadStatusChanged")

    ' create/set global fields with Channel dimensions (m.global.channelWidth/channelHeight)
    setChannelWidthHeightFromRootScene()
end sub

'-------------------------------------------------------------------
' Callback triggered by Flow's when their m.top.event field is set.
'
' Supported triggers:
'   * playButtonSelected - transition to ContentFlow
'   * streamInfoReceived - populates global streamInfo field
'   * cancelStream - transition to DetailsFlow
'
' Params:
'   * event as roSGNodeEvent - contains the Flow event data
'-------------------------------------------------------------------
sub onFlowEvent(event as object)
    data = event.GetData()
    trace("onFlowEvent(trigger='%s')".format(data.trigger))

    if data.trigger = "playButtonSelected" then
        showFlow("RafContentFlow")  ' RAF Truex Integration
    else if data.trigger = "cancelStream" then
        showFlow("DetailsFlow")
    end if
end sub

'---------------------------------------------------------------------------------
' Callback triggered when the True[X] ComponentLibrary's loadStatus field is set.
'
' Replaces LoadingFlow with DetailsFlow upon success.
'
' Params:
'   * event as roSGNodeEvent - use event.GetData() to get the loadStatus
'---------------------------------------------------------------------------------
sub onTruexLibraryLoadStatusChanged(event as Object)
    ' make sure tarLibrary has been initialized
    if m.tarLibrary = invalid then return

    trace("onTruexLibraryLoadStatusChanged() --- loadStatus: '%s')".format(m.tarLibrary.loadStatus))

    ' check the library's loadStatus
    if m.tarLibrary.loadStatus = "ready" then
        m.global.addFields({ "___truexLibrary": m.tarLibrary })

        ' present the DetailsFlow now that the Truex library is ready
        showFlow("DetailsFlow")
    else if m.tarLibrary.loadStatus = "failed" then
        ' present the DetailsFlow, streams should use standard ads since the Truex library couldn't be loaded
        if m.global.streamInfo <> invalid then showFlow("DetailsFlow")
    end if
end sub

'----------------------------------------------------------------------------------
' Instantiates and presents a new Flow component of the given name.
'
' The current Flow is not removed until the new Flow is successfully instantiated.
'
' Params:
'   * flowName as String - required; the component name of the new Flow
'----------------------------------------------------------------------------------
sub showFlow(flowName as String)
    trace("showFlow(flowName: '%s')".format(flowName))

    ' flowName must be provided
    if flowName = invalid then return

    ' make sure the requested Flow can be instantiated before removing current Flow
    flow = CreateObject("roSGNode", flowName)
    if flow <> invalid then removeCurrentFlow() else return

    ' listen for Flow events on the new flow
    flow.ObserveField("event", "onFlowEvent")

    ' add the new Flow to the layout
    m.rootLayout.AppendChild(flow)

    ' update currentFlow reference and give it focus
    m.currentFlow = flow
    m.currentFlow.SetFocus(true)
end sub

'-----------------------------------------------------------------------
' Clears m.currentFlow's event listener and removes it from the layout.
'
' Does nothing if m.currentFlow is not set.
'-----------------------------------------------------------------------
sub removeCurrentFlow()
    trace("removeCurrentFlow()", m.currentFlow)

    if m.currentFlow <> invalid then
        m.currentFlow.UnobserveField("event")
        m.currentFlow.visible = false
        m.currentFlow.SetFocus(false)
        m.rootLayout.RemoveChild(m.currentFlow)
        m.currentFlow = invalid
    end if
end sub
