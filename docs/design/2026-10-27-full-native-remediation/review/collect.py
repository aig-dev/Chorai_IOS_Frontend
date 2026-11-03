#!/usr/bin/env python3
"""Collect named, unmodified native App screenshots. Dry-run unless --publish.

Only exported xcresult PNGs are copied. Approved reference images are linked.
Batch metadata is explicit: never infer a screenshot's theme or build from pixels.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil

REPO = Path('/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend')
REVIEW = REPO / 'docs/design/2026-10-27-full-native-remediation/review'
REFS = REPO / 'docs/design/2026-10-21-native-visual-reform/revisions'
DEFAULT_NOTE = '沿用共享原生视觉体系；该页面／子状态没有单独确认过的原型截图。保留现有功能与接口。'
CATALOG = {}


def page(key, label, names, reference=None, note=None):
    for name in names.split('|'):
        CATALOG[name] = dict(id=key, label=label, referencePattern=reference,
                             note=note or DEFAULT_NOTE, order=len(CATALOG))


page('home', 'Home · 我的笔记', 'Native reform Home|review-home|review-home-spacing',
     'v6-feature-journeys/screenshots/home-{theme}.png', '对照 V6 Home 的开放正文列表；排序使用既有真实选项，示例标签不是新增栏目。')
page('home-menu', 'Home · 本人笔记菜单', 'Fidelity native Home menu')
page('home-sort', 'Home · 排序菜单', 'review-home-sort-menu', note='既有四项排序的系统 Menu；没有独立确认的菜单截图，不将原型样例分类写入产品。')
page('editor', '编辑器 · 已有笔记', 'Fidelity real editor|review-editor-existing',
     'v6-feature-journeys/screenshots/editor-{theme}.png', '对照 V6 编辑器；真实单正文编辑页，保存与私有状态遵循原有数据模型。')
page('editor-short', '编辑器 · 短笔记', 'review-editor-short-existing')
page('editor-empty', '编辑器 · 空白草稿', 'review-editor-empty')
page('editor-keyboard', '编辑器 · 键盘', 'review-editor-keyboard')
page('editor-keyboard-dismissed', '编辑器 · 收起键盘', 'review-editor-after-keyboard-dismiss')
page('editor-tools', '编辑器 · 工具', 'review-editor-tools|fidelity-editor-menu-from-keyboard')
page('editor-typed', '编辑器 · 输入后', 'review-editor-typed')
page('explore', 'Explore · 固定滑卡', 'fidelity-explore-deck|remediation-explore-summary',
     'v9-fixed-deck-reader/screenshots/v9-explore-photo-{theme}.png', '对照 V9 固定滑卡；摘要点开全文，保留真实收藏与浏览规则。')
page('explore-long', 'Explore · 长内容摘要', 'remediation-explore-long-summary',
     'v9-fixed-deck-reader/screenshots/v9-explore-essay-{theme}.png', '对照 V9 长内容摘要；卡片外框固定，正文不在卡片内部纵向滚动。')
page('grid', 'Explore · Grid', 'Native reform Grid',
     'v8-grid-brush/screenshots/levels-grid-{theme}.png', '对照 V8 Grid；默认保留等级笔触，隐藏小 Chora，点入详情查看完整内容。')
page('explore-menu', 'Explore · 更多菜单', 'fidelity-explore-native-menu')
page('explore-search', 'Explore · 搜索', 'remediation-explore-search', note='真实搜索呈现与六条只读样本；fixture 不模拟查询匹配或相关性排序。无单独确认原型。')
page('explore-search-menu', 'Explore · 搜索菜单', 'remediation-explore-search-menu')
page('reader', '阅读详情 · 正文', 'Native reform reader',
     'v9-fixed-deck-reader/screenshots/v9-reader-photo-{theme}.png', '对照 V9 开放正文阅读；此离线样本为文字，原稿的示例图片不属于这条真实样本。等级身份区与原作者、收藏、评论等操作保留。')
page('reader-long', '阅读详情 · 长文', 'remediation-reader-document',
     'v9-fixed-deck-reader/screenshots/v9-reader-essay-{theme}.png', '对照 V9 长文阅读；完整正文直接成为页面内容，不套大卡片。')
page('spark', 'Spark · 结果', 'fidelity-spark-results',
     'v6-feature-journeys/screenshots/spark-results-{theme}.png', '对照 V6 Spark；真实状态机与离线结果，未发起真实 AI 生成。')
page('spark-deeper', 'Spark · 继续探索', 'fidelity-spark-deeper',
     'v6-feature-journeys/screenshots/spark-deeper-{theme}.png', '对照 V6 Spark 深层结果；离线样本验证既有链路，不代表服务生成成功。')
page('spark-header-menu', 'Spark · 顶部菜单', 'remediation-spark-header-menu')
page('spark-result-menu', 'Spark · 结果菜单', 'remediation-spark-result-menu')
page('merge-selection', 'Merge · 选材', 'fidelity-merge-selection',
     'v6-feature-journeys/screenshots/merge-selection-{theme}.png', '对照 V6 选材；沿用固定来源及既有 2–8 条来源约束。')
page('merge-selected', 'Merge · 已选来源', 'fidelity-merge-selected',
     'v6-feature-journeys/screenshots/merge-selected-{theme}.png', '对照 V6 已选来源；实际选择状态来自既有状态机与离线样本。')
page('merge-result', 'Merge · 结果编辑', 'fidelity-merge-created-result|fidelity-merge-result',
     'v6-feature-journeys/screenshots/merge-ready-{theme}.png', '对照 V6 结果编辑；离线结果不代表真实生成、Accept 或服务器保存已完成。')
for key, label, name in [
    ('report', '举报 · 原因选择', 'fidelity-report'),
    ('link', 'Link · 关联选择', 'fidelity-link'),
    ('share-error', '分享 · 离线拒绝', 'fidelity-share-offline-error'),
    ('sidebar', '侧栏', 'remediation-sidebar'),
    ('settings', '设置', 'remediation-settings'),
    ('edit-profile', '编辑资料', 'edit-profile-empty-background'),
    ('public-profile', '公开作者资料', 'remediation-public-profile'),
    ('my-profile', '我的资料', 'remediation-my-profile'),
    ('followers', '关注者名单', 'remediation-followers'),
    ('privacy', '账户与隐私', 'remediation-account-privacy'),
    ('privacy-error', '隐私 · 写入失败回滚', 'remediation-privacy-failed-save'),
    ('blocked-users', '已屏蔽用户', 'remediation-blocked-users'),
    ('trash', '废纸篓', 'remediation-trash'),
    ('trash-confirm', '废纸篓 · 永久删除确认', 'remediation-trash-confirmation'),
    ('trash-error', '废纸篓 · 离线删除失败', 'remediation-trash-failed-delete'),
    ('chat-list', 'Chat · 会话列表', 'remediation-chat-list'),
    ('chat', 'Chat · 会话正文', 'remediation-chat-conversation'),
    ('chat-keyboard', 'Chat · 键盘与发送', 'remediation-chat-keyboard-send'),
    ('chat-reply', 'Chat · 离线示例回复', 'remediation-chat-fixture-reply'),
    ('chora', 'Chora · 身份与成长', 'remediation-chora-identity-growth'),
    ('chora-growth', 'Chora · 成长详情', 'remediation-chora-growth'),
    ('chora-sources', 'Chora · 来源', 'remediation-chora-sources'),
    ('chora-history', 'Chora · 本地会话历史', 'remediation-chora-chat-history'),
    ('invitations', '邀请与积分', 'remediation-invitations-credits'),
    ('invitation-history', '邀请 · 历史', 'remediation-invitation-history'),
    ('invitation-rewards', '邀请 · 奖励空态', 'remediation-invitation-rewards'),
    ('credit-ledger', '积分 · 明细空态', 'remediation-credit-ledger'),
    ('notifications', '通知', 'remediation-notifications'),
    ('notifications-unread', '通知 · 未读', 'remediation-notifications-unread'),
    ('notification-detail', '通知 · 详情', 'remediation-notification-detail'),
    ('discovery', 'Discovery Path · 来源路径', 'remediation-discovery-path'),
    ('discovery-menu', 'Discovery Path · 更多菜单', 'remediation-discovery-path-menu'),
    ('sign-in', '登录', 'remediation-sign-in'),
    ('private-beta', 'Private Beta · 入口', 'remediation-private-beta'),
    ('sign-up', '注册', 'remediation-sign-up'),
    ('editor-read-only', '编辑器 · 兼容内容只读', 'card-editor-compatibility-blocked'),
    ('editor-menu-keyboard-dismissed', '编辑器 · 工具菜单收起键盘', 'card-editor-native-menu-keyboard-dismissed'),
    ('chat-recovery', 'Chat · 恢复生成入口', 'chat-agent-recovery-available'),
    ('chat-recovery-typing', 'Chat · 恢复后的输入状态', 'chat-agent-recovery-state'),
    ('explore-large', 'Explore · 辅助字号', 'remediation-explore-accessibility-size'),
    ('reader-large', '阅读详情 · 辅助字号', 'remediation-reader-accessibility-size'),
    ('chat-large', 'Chat · 辅助字号／输入中', 'remediation-chat-accessibility-size'),
    ('chat-large-idle', 'Chat · 辅助字号／普通标题', 'remediation-chat-accessibility-size-idle'),
    ('comments-keyboard', '评论 · 键盘与回复', 'comments-root-keyboard'),
    ('comments-reopened', '评论 · 重新打开', 'comments-root-reopened'),
    ('comments-over-spark', '评论 · Spark 中回复', 'comments-over-spark-keyboard'),
    ('comments-returned-to-spark', '评论 · 返回 Spark', 'comments-returned-to-spark'),
    ('comments-reopened-over-spark', '评论 · 拖动关闭后重新打开', 'comments-spark-reopened-after-drag'),
    ('link-keyboard', 'Link · 键盘与选择', 'link-root-keyboard'),
    ('link-over-sheet', 'Link · 上层页面内选择', 'link-over-existing-sheet'),
    ('link-returned-to-origin', 'Link · 返回原页面', 'link-returned-to-origin'),
]:
    page(key, label, name)
for index, label in enumerate(['文字', '长文', '引用', '清单', '代码', '刊物摘录']):
    page(f'search-summary-{index}', f'搜索摘要 · 样本 {index + 1}／{label}', f'search-summary-{index}',
         note='六种已有只读内容样本的固定尺寸呈现。fixture 不模拟真实查询匹配、相关性或服务可用性；无单独确认原型。')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_results(log):
    outcomes = {}
    if log:
        for cls, method, result in re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed)", Path(log).read_text()):
            outcomes[f'{cls.rsplit(".", 1)[-1]}/{method}()'] = result
    return outcomes


def collect(config, output):
    records, skipped = [], []
    catalog = {**CATALOG, **config.get('capture_overrides', {})}
    for batch in config['batches']:
        if not batch.get('enabled', True):
            continue
        if batch['theme'] not in ['light', 'dark']:
            raise ValueError('Every batch needs an explicit light/dark theme')
        manifest = Path(batch['manifest']).resolve(strict=True)
        result = Path(batch['result']).resolve(strict=True)
        outcomes = test_results(batch.get('log'))
        for test in json.loads(manifest.read_text()):
            outcome = outcomes.get(test['testIdentifier'], 'unknown')
            for item in test['attachments']:
                filename = item['exportedFileName']
                name = re.sub(r'_\d+_[0-9A-Fa-f-]{36}\.png$', '', item.get('suggestedHumanReadableName', ''))
                reason = None
                if not filename.lower().endswith('.png'):
                    continue
                if test['testIdentifier'] in batch.get('exclude_tests', []):
                    reason = 'explicitly-excluded-test'
                elif outcome != 'passed':
                    reason = 'test-did-not-pass-' + outcome
                elif name in batch.get('exclude_names', []):
                    reason = 'explicitly-excluded-batch-capture'
                elif item.get('isAssociatedWithFailure'):
                    reason = 'automatic-failure-attachment'
                elif re.search(r'^(Screenshot|Failure|Debug)|debug|marker|hierarchy', name, re.I):
                    reason = 'automatic-or-debug-image'
                elif name in config.get('ignore_names', []):
                    reason = 'explicitly-ignored'
                elif name not in catalog:
                    reason = 'unmapped-named-image'
                if reason:
                    skipped.append(dict(batch=batch['id'], name=name, file=filename, reason=reason,
                                        testIdentifier=test['testIdentifier'], testOutcome=outcome))
                    continue
                spec = catalog[name]
                source = (manifest.parent / filename).resolve(strict=True)
                if source.parent != manifest.parent:
                    raise ValueError(f'Attachment escapes manifest directory: {source}')
                if source.read_bytes()[:8] != b'\x89PNG\r\n\x1a\n':
                    raise ValueError(f'Not a PNG: {source}')
                digest = sha(source)
                theme, key = batch['theme'], spec['id']
                if not re.fullmatch(r'[a-z0-9-]+', key):
                    raise ValueError(f'Invalid capture ID: {key}')
                note = spec.get('note', DEFAULT_NOTE)
                record = dict(id=key, label=spec['label'], theme=theme,
                    image=f'images/{key}-{theme}-{digest[:12]}.png', timestamp=item['timestamp'],
                    build=batch['build'], note=note, batch=batch['id'], result=str(result),
                    testIdentifier=test['testIdentifier'], testOutcome=outcome,
                    hash=digest, source=str(source), manifest=str(manifest),
                    attachmentName=name, exportedFileName=filename, deviceName=item.get('deviceName'),
                    deviceId=item.get('deviceId'), order=spec.get('order', 1000))
                if spec.get('referencePattern'):
                    reference = (REFS / spec['referencePattern'].format(theme=theme)).resolve(strict=True)
                    record['reference'] = os.path.relpath(reference, output)
                    record['referenceLabel'] = spec['referencePattern'].split('/')[0].split('-')[0].upper() + ' · 保留的确认稿'
                    record['referenceHash'] = sha(reference)
                records.append(record)
    selected = {}
    for record in sorted(records, key=lambda r: (r['timestamp'], r['batch'], r['source'])):
        selected[(record['id'], record['theme'])] = record
    shots = sorted(selected.values(), key=lambda r: (r['order'], r['id'], r['theme']))
    return dict(schemaVersion=2, boundary='Only named captures from passed tests are published. Actual App offline fixture evidence, not live-service or visual sign-off.',
                batches=config['batches'], captures=shots, candidates=records, skipped=skipped)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=REVIEW / 'batches.json')
    parser.add_argument('--publish', action='store_true', help='Copy PNGs and generate captures.js/evidence.json after publish_ready is true')
    parser.add_argument('--plan', type=Path, help='Optional JSON plan, normally under /tmp; does not copy PNGs')
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    output = Path(config.get('output', str(REVIEW))).resolve()
    if output != REVIEW.resolve():
        raise ValueError('Output is restricted to this native remediation review directory')
    evidence = collect(config, output)
    unknown = [s for s in evidence['skipped'] if s['reason'] == 'unmapped-named-image']
    if args.plan:
        args.plan.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n')
    if args.publish:
        if config.get('publish_ready') is not True:
            raise ValueError('Final batches are not approved: set publish_ready only after the final capture list is agreed')
        if unknown:
            raise ValueError(f'Unmapped named captures: {[x["name"] for x in unknown]}; add capture_overrides or ignore_names')
        output.mkdir(parents=True, exist_ok=True)
        for shot in evidence['captures']:
            destination = output / shot['image']
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.exists() and sha(destination) != shot['hash']:
                raise ValueError(f'Existing capture has different bytes: {destination}')
            if not destination.exists():
                shutil.copy2(shot['source'], destination)
            if sha(destination) != shot['hash']:
                raise ValueError(f'Copy checksum mismatch: {destination}')
        public_keys = ['id', 'label', 'theme', 'image', 'timestamp', 'build', 'reference', 'referenceLabel', 'note']
        public = [{k: shot[k] for k in public_keys if k in shot} for shot in evidence['captures']]
        (output / 'captures.js').write_text('window.CHORAI_CAPTURES = ' + json.dumps(public, ensure_ascii=False, indent=2) + ';\n')
        (output / 'evidence.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(dict(published=args.publish, selected=len(evidence['captures']), candidates=len(evidence['candidates']),
                          skipped=len(evidence['skipped']), unmapped=[x['name'] for x in unknown],
                          missingThemes={key: sorted({'light', 'dark'} - {s['theme'] for s in evidence['captures'] if s['id'] == key})
                                         for key in dict.fromkeys(s['id'] for s in evidence['captures'])}), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
