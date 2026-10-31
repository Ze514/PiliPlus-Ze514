import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_insets_safe_area.dart';
import 'package:PiliPlus/pages/webdav/webdav.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

class WebDavSettingPage extends StatefulWidget {
  const WebDavSettingPage({
    super.key,
    this.showAppBar = true,
  });

  final bool showAppBar;

  @override
  State<WebDavSettingPage> createState() => _WebDavSettingPageState();
}

class _WebDavSettingPageState extends State<WebDavSettingPage> {
  final _uriCtr = TextEditingController(text: Pref.webdavUri);
  final _usernameCtr = TextEditingController(text: Pref.webdavUsername);
  final _passwordCtr = TextEditingController(text: Pref.webdavPassword);
  final _directoryCtr = TextEditingController(text: Pref.webdavDirectory);
  bool _obscureText = true;

  @override
  void dispose() {
    _uriCtr.dispose();
    _usernameCtr.dispose();
    _passwordCtr.dispose();
    _directoryCtr.dispose();
    super.dispose();
  }

  Future<void> _restore(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: const Text('恢复设置'),
      content: const Text(
        '将用云端备份覆盖本机的设置与视频设置，备份中的评论记录会合并导入。\n'
        '恢复前会在本机保存一份当前设置快照，误操作时可手工回滚。\n'
        '是否继续？',
      ),
    );
    if (confirmed) {
      await WebDav().restore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showAppBar = widget.showAppBar;
    final padding = MediaQuery.viewPaddingOf(context);
    return SimpleScaffold(
      appBar: showAppBar ? AppBar(title: const Text('WebDAV 设置')) : null,
      body: ViewInsetsSafeArea(
        child: ListView(
          padding: padding.copyWith(
            top: 20,
            left: 20 + (showAppBar ? padding.left : 0),
            right: 20 + (showAppBar ? padding.right : 0),
            bottom: padding.bottom + 100,
          ),
          children: [
            TextField(
              controller: _uriCtr,
              decoration: const InputDecoration(
                labelText: '地址',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _usernameCtr,
              decoration: const InputDecoration(
                labelText: '用户',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordCtr,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: '密码',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscureText = !_obscureText),
                  icon: _obscureText
                      ? const Icon(Icons.visibility)
                      : const Icon(Icons.visibility_off),
                ),
              ),
              obscureText: _obscureText,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _directoryCtr,
              decoration: const InputDecoration(
                labelText: '路径',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '备份内容：设置、视频设置与评论记录（不含 WebDAV 账号密码）',
              style: TextStyle(
                fontSize: 12,
                color: ColorScheme.of(context).outline,
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<WebDavTask?>(
              valueListenable: WebDav().task,
              builder: (context, task, _) {
                final busy = task != null;
                return Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          shape: const RoundedRectangleBorder(
                            borderRadius: Style.mdRadius,
                          ),
                        ),
                        onPressed: busy ? null : WebDav().backup,
                        child: Text(
                          task == WebDavTask.backup ? '备份中…' : '备份设置',
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          shape: const RoundedRectangleBorder(
                            borderRadius: Style.mdRadius,
                          ),
                        ),
                        onPressed: busy ? null : () => _restore(context),
                        child: Text(
                          task == WebDavTask.restore ? '恢复中…' : '恢复设置',
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      fab: Padding(
        padding: .only(
          right: kFloatingActionButtonMargin + (showAppBar ? padding.right : 0),
          bottom: kFloatingActionButtonMargin + padding.bottom,
        ),
        child: ViewInsetsSafeArea(
          child: FloatingActionButton(
            child: const Icon(Icons.save),
            onPressed: () async {
              await GStorage.setting.putAll({
                SettingBoxKey.webdavUri: _uriCtr.text,
                SettingBoxKey.webdavUsername: _usernameCtr.text,
                SettingBoxKey.webdavPassword: _passwordCtr.text,
                SettingBoxKey.webdavDirectory: _directoryCtr.text,
              });
              if (_uriCtr.text.isEmpty) {
                return;
              }
              try {
                final res = await WebDav().init();
                if (res.first) {
                  SmartDialog.showToast('配置成功');
                } else {
                  SmartDialog.showToast('配置失败: ${res.second}');
                }
              } catch (e) {
                SmartDialog.showToast('配置失败: ${e.toString()}');
                return;
              }
            },
          ),
        ),
      ),
    );
  }
}
