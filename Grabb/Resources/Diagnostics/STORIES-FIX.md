# Stories test build

The Stories extractor is adapted from yt-dlp PR #17885 by 0xvd and contributors,
under Unlicense/public domain, pinned to revision
`3e089b44ea159f6057d8792ae0abc0e9e33127b9`:
https://github.com/yt-dlp/yt-dlp/pull/17885

It is loaded only for Instagram Stories. The app keeps its bundled yt-dlp version
for YouTube, Instagram posts/Reels and other sites.

Local adaptations: profile lookup is bounded to one extra page; existing `reels`
API responses are preserved; image Stories are retained; requested missing Stories
fail explicitly; missing page tokens stop the GraphQL fallback. No watched-state
endpoint is called. Logging identifies the patch revision.

This is an experimental, unmerged upstream patch. Offline fixtures validate the
parsing and fallback paths, not whether Instagram accepts a user's session.
