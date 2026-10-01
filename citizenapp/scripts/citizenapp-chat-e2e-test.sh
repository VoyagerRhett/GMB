#!/usr/bin/env bash
# 已安装的两台公民 App 真机黑盒验收：iPhone XCTest + Pixel ADB UI。
# 不构建、不安装、不清空 App；身份及目标联系人不唯一时不发送。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_TEST="$SCRIPT_DIR/citizenapp-ios-ui-test.sh"
export CITIZENAPP_UI_TEST_WORK_DIR="${CITIZENAPP_UI_TEST_WORK_DIR:-/Users/rhett/TATA/tataconsole/target/local-verification/citizenapp-chat-e2e-ios}"

python3 - "$IOS_TEST" <<'PY'
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

IOS_TEST = sys.argv[1]
PACKAGE = 'com.crcfrcn.citizenapp'
CID_PATTERN = re.compile(r'CN[0-9]{3}-CTZN[0-9]-[0-9]{9}-[0-9]{4}')
MARKER = 'CITIZEN_E2E_%010d_%06d' % (int(time.time()), os.getpid() % 1000000)


def command(args, *, timeout=30, input_text=None):
    result = subprocess.run(args, input=input_text, text=True, capture_output=True,
                            timeout=timeout, check=False)
    if result.returncode != 0:
        raise RuntimeError('%s 失败：%s' % (args[0], result.stderr[-500:]))
    return result.stdout


def ios(stage, *, peer=None):
    env = os.environ.copy()
    env['CITIZENAPP_UI_TEST_ONLY'] = stage
    if peer is not None:
        env['TEST_RUNNER_CHAT_E2E_PEER_CID'] = peer
        env['TEST_RUNNER_CHAT_E2E_MARKER'] = MARKER
    result = subprocess.run([IOS_TEST], env=env, text=True, capture_output=True,
                            timeout=1800, check=False)
    if result.returncode != 0:
        # 仅输出测试阶段与尾部诊断，避免把设备 UI 快照写入控制台。
        lines = [line for line in (result.stdout + '\n' + result.stderr).splitlines()
                 if re.search(r'failed|error|cancel|认证|UI 测试失败', line, re.I)]
        diagnostic = '\n'.join(lines[-8:])
        diagnostic = CID_PATTERN.sub('[公民号已隐藏]', diagnostic)
        raise RuntimeError('iPhone XCTest %s 失败：%s' % (stage, diagnostic))
    return result.stdout


def android_nodes():
    for attempt in range(3):
        try:
            raw = command(['adb', 'exec-out', 'uiautomator', 'dump', '/dev/tty'], timeout=25)
            break
        except RuntimeError as error:
            if 'no devices/emulators found' not in str(error) or attempt == 2:
                raise
            time.sleep(2)
    start = raw.find('<?xml')
    end = raw.rfind('</hierarchy>')
    if start < 0 or end < 0:
        raise RuntimeError('Pixel 无法读取当前界面层级')
    root = ET.fromstring(raw[start:end + len('</hierarchy>')])
    return list(root.iter('node'))


def node_label(node):
    return (node.get('text') or '') + ' ' + (node.get('content-desc') or '')


def matching(text, *, exact=False):
    return [node for node in android_nodes() if
            (node_label(node).strip() == text if exact else text in node_label(node))]


def await_nodes(text, *, exact=False, timeout=60):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found = matching(text, exact=exact)
        if found:
            return found
        time.sleep(2)
    raise RuntimeError('Pixel 等待界面元素超时：%s' % text)


def tap_node(node):
    match = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.get('bounds', ''))
    if not match:
        raise RuntimeError('Pixel 界面目标没有有效边界')
    left, top, right, bottom = map(int, match.groups())
    if right <= left or bottom <= top:
        raise RuntimeError('Pixel 界面目标边界无效')
    command(['adb', 'shell', 'input', 'tap', str((left + right) // 2),
             str((top + bottom) // 2)])


def tap_unique(text, *, exact=False, timeout=30):
    found = await_nodes(text, exact=exact, timeout=timeout)
    if len(found) != 1:
        raise RuntimeError('Pixel 界面目标不唯一：%s' % text)
    tap_node(found[0])


def start_android():
    command(['adb', 'shell', 'am', 'force-stop', PACKAGE])
    command(['adb', 'shell', 'am', 'start', '-n', PACKAGE + '/.MainActivity'])
    await_nodes('聊天', timeout=45)


def android_identity():
    start_android()
    tap_unique('我的')
    tap_unique('注册与查看')
    await_nodes('公民号', timeout=30)
    values = sorted(set(match.group(0) for node in android_nodes()
                        for match in CID_PATTERN.finditer(node_label(node))))
    if len(values) != 1:
        raise RuntimeError('Pixel 本机公民号无法唯一读取')
    command(['adb', 'shell', 'input', 'keyevent', '4'])
    return values[0]


def open_android_peer(peer):
    tap_unique('聊天')
    tap_unique('新建')
    tap_unique('发私信', exact=True)
    await_nodes('选择联系人', timeout=30)
    tap_unique('公民号：' + peer, exact=True, timeout=30)
    await_nodes('输入消息', timeout=30)


def android_send_text(value):
    if not re.fullmatch(r'[A-Z0-9_]+', value):
        raise RuntimeError('Pixel 测试文字必须是无空格 ASCII 标记')
    tap_unique('输入消息')
    command(['adb', 'shell', 'input', 'text', value])
    command(['adb', 'shell', 'input', 'keyevent', '66'])
    await_nodes(value, exact=True, timeout=25)


def android_send_sticker():
    tap_unique('表情和贴纸')
    tap_unique('贴纸', exact=True)
    nodes = android_nodes()
    tabs = [node for node in nodes if node.get('text') == '贴纸']
    if len(tabs) != 1:
        raise RuntimeError('Pixel 贴纸面板未打开')
    # SDK 固定五列网格；点击第一枚贴纸，不依赖图像资产的本地化名称。
    bounds = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', tabs[0].get('bounds', ''))
    if not bounds:
        raise RuntimeError('Pixel 贴纸面板边界无效')
    left, _, right, bottom = map(int, bounds.groups())
    command(['adb', 'shell', 'input', 'tap', str(left + max(24, (right-left)//10)),
             str(bottom + 42)])
    await_nodes('[贴纸]', timeout=30)


def verify_android_after_restart():
    start_android()
    open_android_peer(iphone_cid)
    for value in [MARKER, 'PIXEL_' + MARKER, 'AFTER_RESTART_' + MARKER]:
        matches = await_nodes(value, exact=True, timeout=60)
        if len(matches) != 1:
            raise RuntimeError('Pixel 重启后消息重复或缺失')


devices = command(['adb', 'devices', '-l'])
if len(re.findall(r'^\S+\s+device\b', devices, re.MULTILINE)) != 1 or 'Pixel_8a' not in devices:
    raise RuntimeError('必须且只能连接一台 Pixel 8a')

iphone_output = ios('testChatE2EReadIdentity')
cid_matches = re.findall(r'CHAT_E2E_IPHONE_CID=(CN[0-9]{3}-CTZN[0-9]-[0-9]{9}-[0-9]{4})', iphone_output)
if len(cid_matches) != 1:
    raise RuntimeError('iPhone XCTest 没有唯一返回本机公民号')
iphone_cid = cid_matches[0]
pixel_cid = android_identity()
if iphone_cid == pixel_cid:
    raise RuntimeError('双机必须是不同公民号')
print('[身份] 两台不同公民号已由界面读取；不输出实际号码', flush=True)

# 双向通讯录必须各自准确包含对方。匹配失败时不得发送消息。
open_android_peer(iphone_cid)
print('[前置] Pixel 已打开准确对端私聊', flush=True)
ios('testChatE2ESend', peer=pixel_cid)
print('[发送] iPhone 文字与 emoji 已进入真实会话', flush=True)
await_nodes(MARKER, exact=True, timeout=90)
await_nodes('😀' + MARKER, exact=True, timeout=90)
android_send_text('PIXEL_' + MARKER)
android_send_sticker()
print('[回信] Pixel 文字与贴纸已提交', flush=True)
ios('testChatE2EVerifyRestart', peer=pixel_cid)
verify_android_after_restart()
print('[完成] 双机收发、重启与去重全部通过', flush=True)
PY
