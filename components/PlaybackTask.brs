' Copyright (c) 2019 true[X], Inc. All rights reserved.
'-----------------------------------------------------------------------------------------------------------
' PlaybackTask
'-----------------------------------------------------------------------------------------------------------
' Task responsible for handling all responsibilities surrounding RAF, RAF ad integration, TrueX Ad rendering,
' and simple playback behaviours
'
' Member Variables:
' See setupScopedVariables
'-----------------------------------------------------------------------------------------------------------
Library "Roku_Ads.brs" ' Must be managed in a task or render due to a Roku/RAF implementation requirement

sub init()
    m.top.functionName = "setup"
    m.loggerCat = m.top.subtype()

    trace("init()")
end sub

sub setup()

    setupScopedVariables()
    setupVideo()
    setupRaf()
    setupEvents()
    initPlayback()
end sub

'-------------------------------------------
' Initialize and setup all member variables for easy reference
'-------------------------------------------
sub setupScopedVariables()
    tracE("setupScopedVariables()")

    m.port = createObject("roMessagePort")  ' Event port.  Must be used for events due to render/task thread scoping
    m.adFacade = m.top.adFacade  ' Hold reference to the component for RAF and Truex ad rendering
    m.lastPosition = 0  ' Tracks last position, primarily for seeking purposes
    m.videoPlayer = invalid ' Hold reference to player component from render thread
    m.raf = invalid
    m.currentAdPod = invalid ' Current ad pod in use or processing
end sub

'-------------------------------------------
' Initialize video player
'-----------------------------------------
sub setupVideo()
    trace("setupVideo()")

    videoPlayer = m.top.video
    videoContent = createObject("roSGNode", "ContentNode")

    videoContent.url = "http://ctv.truex.com/assets/reference-app-stream-no-ads-720p.mp4"
    videoContent.length = 22 * 60

    videoContent.title = "The true[X] Employee Experience"
    videoContent.streamFormat = "mp4"
    videoContent.playStart = 0

    videoPlayer.content = videoContent
    videoPlayer.setFocus(true)
    videoPlayer.visible = true
    videoPlayer.observeField("position", m.port)
    videoPlayer.enableCookies()

    m.videoPlayer = videoPlayer
end sub

'-------------------------------------------
' Initialize Roku Ads Framework (RAF)
' Also setup ads via RAF with an ad url
'-----------------------------------------
sub setupRaf()
    trace("setupRaf()")

    raf = Roku_Ads()
    raf.enableAdMeasurements(true)
    raf.setContentGenre("Entertainment")
    raf.setContentId("TrueXSample")

    raf.enableInPodStitching(true)

    raf.setDebugOutput(true) 'debugging
    raf.setAdPrefs(false)

    adUrl = m.top.adUrl

    if adUrl = invalid or adUrl = "" then
        adUrl = "pkg:/res/adpods/vmap-truex.xml" ' Preroll + Midroll Truex experience
        ' adUrl = "pkg:/res/adpod/truex-pod-preroll.xml"  ' Can check individual vast pods. Always assumed to be a preroll pod by RAF.
    end if
    raf.setAdUrl(adUrl)

    m.raf = raf
end sub

'-------------------------------------------
' Setup any task based event listening
'-----------------------------------------
sub setupEvents()
    m.top.observeField("exitPlayback", m.port)
end sub

'-------------------------------------------
' Begins the playback experience and starts the event listener loop
' Will be responsible for checking if there is a preroll and to play it before starting playback
'-----------------------------------------
sub initPlayback()
    trace("initPlayback()")

    shouldContinuePlayback = handleAdPod(getPreroll())

    if not(shouldContinuePlayback) then
        exitContentStream()
        return
    end if

    playContentStream()

    while (true)
        msg = wait(0, m.port)

        traceEventMessage(msg)

        if type(msg) = "roSGNodeEvent" then
            field = msg.getField()

            if field = "position" then
                onPositionChanged(msg)
            else if field = "exitPlayback" then
                exitContentStream()
            end if
        end if
    end while
end sub

'-------------------------------------------
' Stores the last position for player seeking purposes
' Gets ads to process
'
' Params:
'   * event as roAssociativeArray - contains the event data from the port
'-----------------------------------------
sub onPositionChanged(event as Object)
    m.lastPosition = event.getData()

    adPod = m.raf.getAds(event)

    if adPod = invalid or adPod.ads.count() = 0 then
        return
    end if

    shouldContinuePlayback = handleAdPod(adPod)

    if shouldContinuePlayback then
        playContentStream()
    end if
end sub

'-------------------------------------------
' Special ad case where we see if there is a preroll ad to process before starting playback
'
' Return:
'   Preroll AdPod if it exists
'-----------------------------------------
function getPreroll() as Dynamic
    trace("getPreroll()")

    adPods = m.raf.getAds()
    if adPods = invalid then return invalid

    result = invalid
    for each adPod in adPods
        if adPod.rendersequence = "preroll" then
            result = adPod
            exit for
        end if
    end for

    return result
end function

'-------------------------------------------
' Handles checking if there are ads to play before starting/resuming playback
'-----------------------------------------
sub playContentStream()
    trace("playContentStream() -- lastPosition: %d")

    if m.lastPosition > 0 then
        m.videoPlayer.seek = m.lastPosition
    end if

    m.videoPlayer.visible = true
    m.videoPlayer.control = "play"
    m.videoPlayer.setFocus(true)
end sub

'-------------------------------------------
' Hides and stops stream
'-----------------------------------------
sub hideContentStream()
    trace("hideContentStream()")

    if m.videoPlayer <> invalid then
        m.videoPlayer.control = "stop"
        m.videoPlayer.visible = false
    end if
end sub

'-------------------------------------------
' Cleans up the player to get ready to exit playback
' Bubbles up a message playerDisposed property so invoker knows it is finished cleaning up
'-----------------------------------------
sub exitContentStream()
    trace("exitContentStream()")

    if m.videoPlayer <> invalid then
        m.videoPlayer.control = "stop"
    end if

    m.top.playerDisposed = true
end sub

'-------------------------------------------
' General ad handler.  Takes care of seeing for a given pod, to play a truex ad
' or play regular ads
'
' Return:
'   false if playback should not be resumed yet (truex case mainly)
'   true if playback should be resumed (non-ad or certain raf cases)
'-----------------------------------------
function handleAdPod(adPod as Dynamic) as Boolean
    m.currentAdPod = adPod

    ' assume truex can only be the first ad in a pod
    firstAd = adPod.ads[0]

    trace("handleAdPod() -- ads: %d, truexAd: %s".format(adPod.ads.count(), isTruexAd(firstAd).toStr()))

    ' stop the content player
    hideContentStream()

    shouldSkipRemainingAds = false
    shouldContinuePlayback = true

    if isTruexAd(firstAd) then
        ' Need to delete the ad from the pod which is referenced by raf so it plays
        ' ads from the correct index when resulting in non-truex flows (eg. opt out)
        ' If it is not deleted, this pod will attempt to play the truex ad placeholder
        ' when it is passed into raf.showAds()
        adPod.ads.delete(0)
        adPod.duration -= firstAd.duration

        ' Takes thread ownership until complete or exit
        truexAdResult = playTrueXAd(m.top.adFacade, firstAd, adPod.rendersequence)
        shouldSkipRemainingAds = truexAdResult.shouldSkipRemainingAds
        ' emptyMessageQueue(m.port)
    end if

    if not(shouldSkipRemainingAds) then
        ' Takes thread ownership until complete or exit
        shouldContinuePlayback = m.raf.showAds(adPod, invalid, m.adFacade)
    end if

    m.currentAdPod = invalid

    return shouldContinuePlayback
end function

'-------------------------------------------
' Handles responsibility of initializing the TrueX Ad Renderer (TAR) and starting the
' interactive ad experience.  Stops and hides the content video player
'-----------------------------------------
function playTrueXAd(adContainer as Object, truexAdInfo as Object, slotType = "preroll") as Object
    if not(loadTrueXRendererLibrary()) then
      return false
    end if

    port = CreateObject("roMessagePort")

    version = CreateObject("roSGNode", "TruexLibrary:TruexVersion")

    truexAdRenderer = adContainer.createChild("TruexLibrary:TruexAdRenderer")
    truexAdRenderer.observeFieldScoped("event", port)

    ' get channel's design resolution
    rect = m.top.getScene().currentDesignResolution

    ' there are 2 ways how `adParameters` might be defined
    ' - as `Creative[id="super_tag"].Linear.AdParameters` section in VAST - as json string
    ' - as `Creative[id="super_tag"].CompanionAds.Companion.StaticResource[creativeType="application/json"]` as base64 encoded json string
    if truexAdInfo.adparameters <> invalid then
        adParameters = ParseJson(truexAdInfo.adparameters)
    else
        encodedAdParameters = truexAdInfo.companionads[0].url.split("data:application/json;base64,")[1]
        encodedAdParameters = encodedAdParameters.replace(chr(10), "")

        buffer = CreateObject("roByteArray")
        buffer.FromBase64String(encodedAdParameters)

        adParameters = ParseJson(buffer.ToAsciiString())
    end if

    initAction = {
        type: "init",
        adParameters: adParameters,
        slotType: ucase(slotType),

        ' enables cancelStream event types, disable if Channel does not support
        supportsUserCancelStream: true,

        ' Optional parameter, set the verbosity of true[X] logging, from 0 (mute) to 5 (verbose), defaults to 5
        logLevel: 1,

        ' Optional parameter, set the width in pixels of the channel's interface, defaults to 1920
        channelWidth: rect.width,

        ' Optional parameter, set the height in pixels of the channel's interface, defaults to 1080
        channelHeight: rect.height,
    }

    trace("playTrueXAd() -- initializing", FormatJson(initAction))
    truexAdRenderer.action = initAction

    trace("playTrueXAd() -- starting")
    truexAdRenderer.action = { type: "start" }

    result = {
        shouldSkipRemainingAds: false,
        userCancelStream: false,
        error: false,
    }

    while true
        msg = wait(0, port)

        if type(msg) <> "roSGNodeEvent" and msg.GetField() <> "event" then
            continue while
        end if

        truexEvent = msg.GetData()

        trace("handleTruexEvent() - %s".format(FormatJson(truexEvent)))

        ' @see https://github.com/socialvibe/truex-roku-integrations/blob/develop/DOCS.md#handling-events-from-truexadrenderer
        ' "adFreePod" - when the user has earned a credit with true[X].
        '     The channel code should notate that this event has fired, but should not take any further action.
        '     Upon receiving a terminal event, if adFreePod was fired, the channel should skip all remaining ads in the current slot.
        '     If it was not fired, the channel should resume playback without skipping any ads, so the user receives a normal video ad payload.

        ' terminal events
        ' - "noAdsAvailable" - when the true[X] unit has determined it has no ads available to show the current user.
        ' - "adCompleted" - when the true[X] unit is finished with its activities
        ' - "adError" - when the true[X] unit has encountered an unrecoverable error
        ' - "userCancelStream" - ' User exits playback. EG. Typically "back" on choice card
        if truexEvent.type = "adError" then
            if truexEvent.errorMessage <> invalid then
                result.error = truexEvent.errorMessage
            else
                result.error = "unknown error"
            end if

            exit while
        else if truexEvent.type = "noAdsAvailable" then
            exit while
        else if truexEvent.type = "userCancelStream" then
            result.userCancelStream = true
            exit while
        else if truexEvent.type = "adFreePod" then
            result.shouldSkipRemainingAds = true
        else if truexEvent.type = "adCompleted" then
            exit while
        end if
    end while

    trace("playTrueXAd() -- ended", result)

    ' dispose renderer
    truexAdRenderer.visible = false
    truexAdRenderer.setFocus(false)
    truexAdRenderer.unobserveFieldScoped("event")

    if truexAdRenderer.getParent() <> invalid then
        truexAdRenderer.getParent().removeChild(truexAdRenderer)
    end if

    truexAdRenderer = invalid

    return result
end function

'-------------------------------------------
' Helper to see if an ad is TrueX
' Checks if there is an <AdParameter> tag, and the ad server is a qa or prod truex domain
'
' Return:
'   true if TrueX, false if other
'-----------------------------------------
function isTruexAd(adInfo) as Boolean
    prodDomain = "get.truex.com/"
    qaDomain = "qa-get.truex.com/"

    ' has valid `adserver` value, usually it will be truex ad request url
    hasValidAdServer = (adInfo.adserver?.instr?(0, prodDomain) > 0 or adInfo.adserver?.instr?(0, qaDomain) > 0)

    ' there are 2 ways how `adParameters` might be defined
    ' - as `Creative[id="super_tag"].Linear.AdParameters` section in VAST - as json string
    ' - as `Creative[id="super_tag"].CompanionAds.Companion.StaticResource[creativeType="application/json"]` as base64 encoded json string
    hasValidAdParameters = (adInfo.adparameters <> invalid)
    hasValidCompanion = (adInfo.companionads?[0]?.url?.StartsWith?("data:application/json;base64,") = true)

    return hasValidAdServer and (hasValidAdParameters or hasValidCompanion)
end function

function loadTrueXRendererLibrary() as Boolean
    try
        truexVersion = CreateObject("roSGNode", "TruexLibrary:TruexVersion")
    catch e
        ' nothign here
    end try

    if truexVersion = invalid then
        port = CreateObject("roMessagePort")
        truexLibraryUrl = "https://ctv.truex.com/roku/v1/release/TruexAdRenderer-Roku-v1.pkg"

        trace("loadTrueXRendererLibrary() -- loading: %s".format(truexLibraryUrl))

        truexRendererLibrary = CreateObject("roSGNode", "ComponentLibrary")
        truexRendererLibrary.id = "truex-ad-renderer-library"
        truexRendererLibrary.uri = truexLibraryUrl
        truexRendererLibrary.observeFieldScoped("loadStatus", port)

        while true
            msg = wait(10000, port)

            if msg = invalid or type(msg) <> "roSGNodeEvent" then
                exit while
            end if

            if truexRendererLibrary.loadStatus = "ready" then
                m.global.addFields({ "___truexLibrary": truexRendererLibrary })
                exit while
            else if truexRendererLibrary.loadStatus = "failed" then
                exit while
            end if
        end while

        trace("loadTrueXRendererLibrary() -- loadStatus: %s".format(truexRendererLibrary.loadStatus))
    end if

    truexVersion = CreateObject("roSGNode", "TruexLibrary:TruexVersion")

    if truexVersion = invalid then
        return false
    end if

    trace("loadTrueXRendererLibrary() -- version: %s".format(truexVersion.value))

    return true
end function
