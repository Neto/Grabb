# Adapted from yt-dlp PR #17885 (Unlicense/public domain), by 0xvd and contributors.
# Pinned revision: 3e089b44ea159f6057d8792ae0abc0e9e33127b9
# https://github.com/yt-dlp/yt-dlp/pull/17885
import json
import re

from yt_dlp.extractor.instagram import InstagramStoryIE as _InstagramStoryIE, _pk_to_id
from yt_dlp.utils import ExtractorError, filter_dict, str_or_none, traverse_obj, urlencode_postdata


class InstagramStoryFixIE(_InstagramStoryIE, plugin_name='GrabbStoriesPR17885'):
    _DTSG = None

    def _get_fb_dstg(self, webpage=None):
        if self._DTSG:
            return self._DTSG

        if not webpage:
            return None

        self._DTSG = self._search_regex(
            [
                r'\bdtsg"\s*:\s*{\s*"token":\s*["\']([^"\']+)["\']',
                r'\b(?:DTSGInitData|DTSGInitialData)",.+?"token":\s*"([^"]+)"',
                r'"f":\s*"(\w+:\d+:\d+[^"]*)"',
            ],
            webpage,
            'Fb Dtsg',
            default=None,
        )
        return self._DTSG

    def _yield_relay_data(self, video_id, webpage):
        for relay in re.findall(r'data-sjs>\s*({.*?})\s*</script>', webpage):
            yield self._parse_json(relay, video_id, fatal=False)

    def _get_user_id(self, webpage, allow_profile=True):
        user_id = traverse_obj(
            re.findall(r'"user":\s*({.+?},(?:.+?}))?,?', webpage),
            (..., {json.loads}, ('user_id', 'instagram_pk'), {str}, any))
        if not user_id:
            user_id = self._search_regex(r'"(?:reel_ids_arr|profile_id|container_id)"\s*:\s*\[?\s*"(\d+)"', webpage, 'User id', default=None)
        if not user_id:
            user = self._search_json(r'"user":', webpage, 'user info', None, default={})
            user_id = traverse_obj(user, 'pk', 'id', expected_type=str_or_none, get_all=False)
        if user_id or not allow_profile:
            return user_id
        user_name = self._search_regex(r'https?://(?:www\.)?instagram\.com/stories/([^/?#]+/?)', webpage, 'user name', default=None)
        if user_name:
            user_webpage = self._download_webpage(f'{self._BASE_URL}{user_name}', None, 'Downloading user page')
            user_id = self._get_user_id(user_webpage, allow_profile=False)
        return user_id

    def _real_extract(self, url):
        self.to_screen('Grabb Stories fix: PR17885@3e089b4 (bounded profile lookup)')
        username, story_id = self._match_valid_url(url).group('user', 'id')
        if username == 'highlights' and not story_id:  # story id is only mandatory for highlights
            raise ExtractorError('Input URL is missing a highlight ID', expected=True)
        display_id = story_id or username
        story_webpage = self._download_webpage(url, display_id, impersonate=self._can_impersonate and self._is_web_app)

        user_id = None
        if username == 'highlights':
            story_info_url = f'highlight:{story_id}'
        else:
            user_id = self._get_user_id(story_webpage)
            if not user_id:  # user id is only mandatory for non-highlights
                raise ExtractorError('Unable to extract user id')
            story_info_url = user_id

        videos = traverse_obj(
            self._yield_relay_data(display_id, story_webpage), (
                ..., 'require', ..., ..., ..., '__bbox',
                'require', ..., ..., ..., '__bbox',
                'result', 'data',
                lambda x, _: x.startswith('xdt_api__v1'),
                ('reels_media', 'edges'),
                lambda _, v: v.get('items') or (v.get('id') or '') == user_id or (story_id and story_id in str(v.get('node', {}).get('id', ''))),
                ('node', None), any),
        )
        if not videos:
            data = self._download_json(
                f'{self._API_BASE_URL}/feed/reels_media/?reel_ids={story_info_url}',
                display_id, headers=self._api_headers,
                impersonate=self._can_impersonate and self._is_web_app, expected_status=500)
            videos = traverse_obj(data, ('reels', story_info_url), 'reel', expected_type=dict)
            if not (videos or 'ok' in (data.get('status') or '')):
                token = self._get_fb_dstg(story_webpage)
                if not token:
                    raise ExtractorError('Instagram did not provide the page token needed for the Stories fallback', expected=True)
                videos = traverse_obj(
                    self._download_json(
                        'https://www.instagram.com/graphql/query',
                        display_id,
                        headers={
                            **self._api_headers,
                            'Content-Type': 'application/x-www-form-urlencoded',
                            'x-root-field-name': 'xdt_api__v1__feed__reels_media',
                        },
                        data=urlencode_postdata({
                            'variables': json.dumps({
                                'reel_ids_arr': [story_info_url],
                                '__relay_internal__pv__PolarisCommunityNoteStoriesLabelEnabledrelayprovider': True,
                            }, separators=(',', ':')),
                            'doc_id': 29341065465524437,
                            'fb_dtsg': token,
                        }),
                        impersonate=self._can_impersonate and self._is_web_app,
                        errnote=False,
                        fatal=False,
                    ),
                    ('data', 'xdt_api__v1__feed__reels_media', 'reels_media', lambda _, x: x['items'], {dict}, any),
                )

        if not videos:
            self.raise_login_required('You need to log in to access this content')
        reel = traverse_obj(videos, user_id, f'highlight:{story_id}', expected_type=dict, get_all=False) or videos
        user_info = reel.get('user') or {}

        full_name = user_info.get('full_name')
        story_title = reel.get('title')
        if not story_title:
            story_title = f'Story by {username}'

        highlights = traverse_obj(reel, ('items', ..., {dict}))
        info_data = []
        for highlight in highlights:
            highlight.setdefault('user', {}).update(user_info)
            highlight_data = self._extract_product(highlight)
            # Keep image Stories too; Grabb already downloads Instagram photos as thumbnails.
            if highlight_data.get('formats') or highlight_data.get('thumbnails'):
                info_data.append({
                    'uploader': full_name,
                    'uploader_id': user_id,
                    'title': story_title,
                    **filter_dict(highlight_data),
                })
        if username != 'highlights' and story_id and not self._yes_playlist(username, story_id):
            selected = traverse_obj(info_data, (lambda _, v: v['id'] == _pk_to_id(story_id), any))
            if not selected:
                raise ExtractorError('This Story is no longer available to this session', expected=True)
            return selected

        return self.playlist_result(info_data, playlist_id=story_id, playlist_title=story_title)
