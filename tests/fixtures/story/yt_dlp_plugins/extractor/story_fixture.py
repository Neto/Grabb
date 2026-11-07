"""Offline responses for the bundled Stories plugin. Never reads browser cookies."""
import json

from yt_dlp.extractor.common import InfoExtractor
from yt_dlp.extractor.instagram import _pk_to_id
from yt_dlp.utils import ExtractorError
from yt_dlp_plugins.extractor.instagram_story_fix import InstagramStoryFixIE


class GrabbStoryFixtureIE(InfoExtractor):
    _VALID_URL = r'grabb-fixture:(?P<id>api|graphql|relay|photo|profile-bound|missing|highlight|legacy-user|missing-token|rate-limit)$'
    IE_NAME = 'grabb:story-fixture'

    def _real_extract(self, url):
        case = self._match_id(url)
        fix = InstagramStoryFixIE(self._downloader)
        user_id, story_id = '123', '456'
        item = {
            'pk': story_id, 'user': {'pk': user_id, 'username': 'fixture', 'full_name': 'Fixture'},
            'video_versions': [] if case == 'photo' else [
                {'url': 'https://example.invalid/fixture.mp4', 'width': 1080, 'height': 1920}],
            'image_versions2': {'candidates': [
                {'url': 'https://example.invalid/fixture.jpg', 'width': 1080, 'height': 1920}]},
        }
        reel = {'id': user_id, 'user': item['user'], 'items': [item]}
        api_key = 'highlight:456' if case == 'highlight' else user_id
        calls = []
        page = '"profile_id":"123" "dtsg":{"token":"FIXTURE_SECRET"}'
        if case == 'legacy-user':
            page = '"user":{"pk":123}'
        if case == 'missing-token':
            page = '"profile_id":"123"'
        if case == 'profile-bound':
            page = 'https://www.instagram.com/stories/fixture/'
        if case == 'relay':
            relay = {'require': [['A', [], [], [{'__bbox': {
                'require': [['B', [], [], [{'__bbox': {'result': {'data': {
                    'xdt_api__v1__feed__reels_media': {'reels_media': [reel]},
                }}}}]]],
            }}]]]}
            page += '<script data-sjs>' + json.dumps(relay) + '</script>'

        def webpage(url, *args, **kwargs):
            calls.append('page')
            assert len(calls) <= 4, 'Unbounded requests'
            return page

        def metadata(url, *args, **kwargs):
            if '/graphql/' in url:
                calls.append('graphql')
                assert case == 'graphql'
                return {'data': {'xdt_api__v1__feed__reels_media': {'reels_media': [reel]}}}
            assert '/feed/reels_media/' in url
            calls.append('api')
            if case == 'rate-limit':
                raise ExtractorError('HTTP Error 429', expected=True)
            return {'status': 'fail'} if case in ('graphql', 'missing-token') else {'reels': {api_key: reel}}

        fix._download_webpage = webpage
        fix._download_json = metadata
        source = f'https://www.instagram.com/stories/{"highlights" if case == "highlight" else "fixture"}/{"999" if case == "missing" else story_id}/'
        try:
            result = fix._real_extract(source)
        except ExtractorError as error:
            assert case in ('profile-bound', 'missing', 'missing-token', 'rate-limit'), str(error)
            if case == 'profile-bound':
                assert calls == ['page', 'page'], calls
            elif case == 'missing':
                assert 'no longer available' in str(error)
            else:
                assert calls == ['page', 'api'], calls
                assert ('token' if case == 'missing-token' else '429') in str(error)
        else:
            if case == 'highlight':
                assert result['_type'] == 'playlist' and len(result['entries']) == 1
                result = result['entries'][0]
            assert result['id'] == _pk_to_id(story_id)
            assert bool(result['formats']) == (case != 'photo')
            assert result['thumbnails']
            expected = ['page'] if case == 'relay' else ['page', 'api', 'graphql'] if case == 'graphql' else ['page', 'api']
            assert calls == expected, calls
        self.to_screen(f'PASS fixture={case} requests={calls}')
        return self.playlist_result([], playlist_id=case)
