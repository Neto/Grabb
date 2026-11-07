from datetime import datetime, timezone

from yt_dlp.extractor.common import InfoExtractor


class GrabbSessionIE(InfoExtractor):
    """Local cookie inspection only; no Instagram URLs or network methods."""

    _VALID_URL = r'grabb:instagram-session$'
    IE_NAME = 'grabb:session'

    def _real_extract(self, url):
        sessions = [
            cookie for cookie in self.cookiejar
            if cookie.name == 'sessionid'
            and (cookie.domain.lstrip('.') == 'instagram.com'
                 or cookie.domain.lstrip('.').endswith('.instagram.com'))
        ]
        self.to_screen(f'[session-check] present={"yes" if sessions else "no"} count={len(sessions)}')
        for cookie in sessions:
            expired = 'yes' if cookie.is_expired() else 'no'
            if cookie.expires is None:
                expires = 'session'
            else:
                try:
                    expires = datetime.fromtimestamp(cookie.expires, timezone.utc).isoformat()
                except (OverflowError, OSError, ValueError):
                    # Report the timestamp as read; guessing units would hide a loader bug.
                    expires = f'out-of-range(raw={cookie.expires})'
                    expired = 'unknown'
            # Never format the cookie itself, its value, or a request header.
            self.to_screen(
                f'[session-check] cookie=sessionid domain={cookie.domain} '
                f'path={cookie.path} expires={expires} '
                f'expired={expired} '
                f'has_value={"yes" if cookie.value else "no"}')
        self.to_screen('[session-check] offline=complete; server acceptance was not tested')
        return self.playlist_result([], playlist_id='local-session-check')
