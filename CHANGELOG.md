# Technical history

Release 1.9.0 (build 21) renames DLALL to Grabb. The bundle identifier is now com.spinoff.Grabb, the update feed is grabb/appcast.xml in Neto/spinoff-updates, and the yt-dlp plugins are grabb:session and grabb:instagram-session. On the first launch, Grabb copies the DLALL settings and moves the history from Application Support/DLALL to Application Support/Grabb. The app also includes Sparkle updates (Grabb > Check for Updates…).

Release 1.8.3 (build 20) has a new app icon: a neon download arrow on a dark rounded square. The sources are Design/MakeIcon.swift and Design/AppIconSource.png.

Release 1.8.2 (build 19) adds the DLALL logo to the bottom right corner of the app window and of the tutorial mock window. The Close button is removed from the tutorial. The tutorial closes with Start Using DLALL or with Esc.

Release 1.8.1 (build 18) updates the tutorial. The animation now plays on a light grey stage, so the dark window of the app is easy to see. The DLALL logo sits in the bottom right corner of the stage. A new step, Upscale low resolution videos, shows the Available and Upscale sections of the Quality menu.

Release 1.8.0 (build 17) adds upscale. The Quality menu has two sections: Available and Upscale. Upscale lists the resolutions above the best resolution of the video. On macOS 26 or later, with a source up to 1080p, the app uses Apple machine learning super resolution (VideoToolbox VTFrameProcessor). Otherwise it uses ffmpeg Lanczos scaling. If the ML step fails, Lanczos runs instead. Each request in Downloads and History is now a long card, and its actions sit in a right column that thin lines divide.

Release 1.7.1 (build 16) changes the look of the controls to clear Liquid Glass. The Downloads and History switch is now one segmented control in the blue bar. The URL row order is Paste, URL field, Quality, Download. The text under the field is removed. The tutorial has a darker background, a Close button and larger Back and Next buttons. Scripts use the notarization profile DLALL.

Release 1.7.0 (build 15) renames the app to DLALL and merges the BaixaTudo version of Ricardo Cavallini with the History tab of release 1.6. The whole interface is now in English. The first launch shows an animated tutorial. Help > Show Tutorial opens it again. The empty state shows only a title and a link to the tutorial.

Build 12 includes a Stories-only plugin adapted from [yt-dlp PR #17885](https://github.com/yt-dlp/yt-dlp/pull/17885), pinned to `3e089b44ea159f6057d8792ae0abc0e9e33127b9`. This experimental patch prefers embedded page data, then the reels API and a GraphQL fallback. Local adaptations bound profile lookup, preserve the existing API shape and retain photo Stories. It requires a specific browser, disables internal retries for Stories and skips the automatic quality probe when pasting a Story URL. Clicking download starts metadata extraction; successful downloads can still perform a second extraction in the existing download phase. Other websites retain their existing extractor. No live Instagram test is run during builds or fixture tests.

Build 13 separates “Cookies for videos” (YouTube, Reels, Instagram posts and other links) from “Cookies for Instagram Stories” (both images and videos, including highlights). On migration, the old specific browser choice is retained for Stories and videos default to “None”. The last successful Stories browser never becomes a preferred browser for video probes. The offline session check uses the Stories preference.

Release 1.5.3 (build 14) disables detailed diagnostics on its first launch, including the preference inherited from the debug builds. Afterwards it respects deliberate changes to the toggle. The offline cookie check and short error log remain available. Stories retain their extractor fix, disabled automatic quality probe and zero internal retries.

