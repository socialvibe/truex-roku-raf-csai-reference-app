Library "Roku_Ads.brs" ' Must be initialized in the task (or main) thread

sub init()
  ? "TRUE[X] >>> PlaybackTask::init()"
  m.top.functionName = "setup"
end sub

sub setup() 
  m.port = createObject("roMessagePort")
  m.adFacade = m.top.adFacade
  m.skipAds = false
  m.isInTruexAd = false

  setupVideo()
  setupRaf()
  startPlayback()
end sub

sub setupVideo()
  ? "TRUE[X] >>> setupVideo()"

  videoPlayer = m.top.video
  videoContent = createObject("roSGNode", "ContentNode")

  ' videoContent.url = "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4"
  ' videoContent.length = 60
  videoContent.url = "http://ctv.truex.com.s3.amazonaws.com/assets/reference-app-stream-no-ads-720p.mp4"
  videoContent.length = 22 * 60

  videoContent.title = "video title"
  videoContent.streamFormat = "mp4"
  videoContent.playStart = 0

  videoPlayer.content = videoContent
  videoPlayer.SetFocus(true)
  videoPlayer.visible = true
  videoPlayer.observeField("position", "onPositionChanged")
  videoPlayer.EnableCookies()

  m.videoPlayer = videoPlayer
end sub

sub setupRaf()
  ? "TRUE[X] >>> setupRaf()"
  raf = Roku_Ads()
  raf.enableAdMeasurements(true)
  raf.setContentGenre("Entertainment")
  raf.setContentId("TrueXSample")

  raf.SetDebugOutput(false) 'debugging
  raf.SetAdPrefs(false)

  adUrl = m.top.adUrl
  if adUrl = invalid OR adUrl = ""
    ' adUrl = "pkg:/res/vast.xml"  ' Regular Ads
    adUrl = "pkg:/res/vast-truex.xml"  ' TrueX preroll + Ads
    ' adUrl = "http://stash.truex.com.s3.amazonaws.com/sample-tags/dfp-dai/roku-vmap/ss_sab-adpod-vast-funimation-preroll.xml"
  end if 
  raf.setAdUrl(adUrl)

  m.raf = raf
end sub

sub startPlayback()
  ? "TRUE[X] >>> startPlayback()"

  checkPreroll() ' Currently doesn't handle secondary ad flows (eg. skip choice card).  Requires letting playback to handle
  if NOT m.isInTruexAd
    m.videoPlayer.control = "play" 'TODO: Should this go in the flow?
  end if

  while(true)
    msg = Wait(0, m.port)
    msgType = type(msg)

    ' ? "event type:" msgType
    if msgType = "roSGNodeEvent"
      field = msg.getField()
      ? "roSGNodeEvent msg.getField()" field
      if field = "position" then 
        onPositionChanged(msg)
      else if field = "event" then
        onTrueXEvent(msg)
      end if
      ' TODO: Video complete event
    end if
  end while
end sub

sub checkPreroll()
  ads = m.raf.getAds()
  if ads = invalid then return

  for each adPod in ads
    if adPod.rendersequence = "preroll"
      handleAds(adPod)
      exit for
    end if
  end for
end sub

sub onPositionChanged(event)
  position = event.getData()

  ads = m.raf.getAds(event)
  handleAds(ads)
end sub

sub onTruexEvent(event)
  data = event.getData()
  eventType = data.type

  ? "TRUE[X] >>> PlaybackTask::onTrueXEvent(): " eventType

  types = {
    "ADSTARTED": "adStarted",
    "ADCOMPLETED": "adCompleted"
    "ADPOSITION": "adPosition",
    "ADERROR": "adError",
    "ADFREEPOD": "adFreePod"
    "NOADSAVAILABLE": "noAdsAvailable",
    "OPTIN": "optIn",
    "OPTOUT": "optOut",
    "USERCANCEL": "userCancel",
    "USERCANCELSTREAM": "userCancelStream",
    "SKIPCARDSHOWN": "skipCardShown"
  }

  ' TODO: Various event formats
  ' TODO: Combine statements into one if statement.  Or something else like SWITCH?

  restorePlaybackEvents = [types.ADCOMPLETED, types.USERCANCEL, types.NOADSAVAILABLE, types.ADERROR]

  if eventType = types.SKIPCARDSHOWN
    ' Showing Skip Card
  else if eventType = types.ADFREEPOD
    m.skipAds = true
  else if arrayUtils_includes(restorePlaybackEvents, eventType)
    restorePlayback()
  else if eventType = types.USERCANCELSTREAM
    exitPlayback()
  end if
end sub

sub handleAds(ads)
  if ads <> invalid AND ads.ads.count() > 0
    firstAd = ads.ads[0] 'Assume truex can only be first ad

    if firstAd.adParameters <> invalid
      if m.skipAds then
        ads.viewed = true ' necessary
        return
      end if

      m.truexAd = firstAd
      m.truexAd.adParameters = parseJSON(m.truexAd.adParameters)
      m.truexAd.renderSequence = ads.renderSequence
      ads.ads.delete(0) ' Removes it from future ad handling for raf

      playTrueXAd()
    else if firstAd.streams <> invalid AND firstAd.creativeid = "truex-test-id"
      ' Hacky conditional above for now.  Probably DELETE this block after
      ' TODO: Figure out how to get metadata into the Roku ad parser.  AdParameters?
      if m.skipAds then
        ads.viewed = true
        return
      end if

      url = firstAd.streams[0].url
      m.truexAd = firstAd
      m.truexAd.renderSequence = ads.renderSequence

      m.truexAd.adParameters = {
        vast_config_url: url,
        placement_hash: "74fca63c733f098340b0a70489035d683024440d" 'Placeholder
      }

      ads.ads.delete(0) ' Removes it from future ad handling for raf
      playTrueXAd()
    else ' Non-TrueX ads
      hidePlayback()
      watchedAd = m.raf.showAds(ads, invalid, m.adFacade) 'Takes thread ownership until complete or exit
      if NOT watchedAd
        exitPlayback()
      else
        restorePlayback()
      end if
    end if
  end if
end sub

sub playTrueXAd()
    ? "TRUE[X] >>> ContentFlow::launchTruexAd() - instantiating TruexAdRenderer ComponentLibrary..."

    ' instantiate TruexAdRenderer and register for event updates
    m.adRenderer = m.top.adFacade.createChild("TruexLibrary:TruexAdRenderer")
    m.adRenderer.observeFieldScoped("event", m.port)

    ' use the companion ad data to initialize the true[X] renderer
    tarInitAction = {
      type: "init",
      adParameters: m.truexAd.adParameters,
      supportsUserCancelStream: true, ' enables cancelStream event types, disable if Channel does not support
      slotType: ucase(m.truexAd.rendersequence),
      logLevel: 1, ' Optional parameter, set the verbosity of true[X] logging, from 0 (mute) to 5 (verbose), defaults to 5
      channelWidth: 1920, ' Optional parameter, set the width in pixels of the channel's interface, defaults to 1920
      channelHeight: 1080 ' Optional parameter, set the height in pixels of the channel's interface, defaults to 1080
    }
    ? "TRUE[X] >>> ContentFlow::launchTruexAd() - initializing TruexAdRenderer with action=";tarInitAction
    m.adRenderer.action = tarInitAction

    hidePlayback()

    ? "TRUE[X] >>> ContentFlow::launchTruexAd() - starting TruexAdRenderer..."
    m.adRenderer.action = { type: "start" }
    m.adRenderer.focusable = true
    m.adRenderer.SetFocus(true)

    m.isInTruexAd = true
end sub

sub hidePlayback()
    m.videoPlayer.control = "stop"
    m.videoPlayer.visible = false
end sub

sub restorePlayback()
    cleanUpAdRenderer()

    m.videoPlayer.visible = true
    m.videoPlayer.control = "play"
    m.videoPlayer.setFocus(true)
end sub

sub exitPlayback()
  cleanUpAdRenderer()
  m.top.playbackEvent = { trigger: "cancelStream" } ' Might want to change this API since this is the flows API to the scene
end sub

sub cleanUpAdRenderer()
  ? "TRUE[X] >>> PlaybackTask::cleanUpAdRenderer(): "
  if m.adRenderer <> invalid then
      m.adRenderer.SetFocus(false)
      m.adRenderer.unobserveFieldScoped("event")
      m.top.removeChild(m.adRenderer)
      m.adRenderer.visible = false
      m.adRenderer = invalid
  end if
end sub