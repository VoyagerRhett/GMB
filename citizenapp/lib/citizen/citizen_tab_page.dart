import 'package:flutter/material.dart';

import 'package:citizenapp/citizen/election/election_tab.dart';
import 'package:citizenapp/citizen/governance/governance_tab.dart';
import 'package:citizenapp/citizen/legislation/legislation_tab.dart';
import 'package:citizenapp/citizen/public/public_page.dart';
import 'package:citizenapp/citizen/feed/proposal_tab.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 底部“公民”Tab 的总入口。
///
/// 仅负责公民域二级导航分发；具体业务分别下沉到 all/legislation/election/governance/public。
class CitizenTabPage extends StatefulWidget {
  const CitizenTabPage({
    super.key,
    this.onPendingVoteCountChanged,
    this.proposalContent,
  });

  final ValueChanged<int>? onPendingVoteCountChanged;
  final Widget? proposalContent;

  @override
  State<CitizenTabPage> createState() => _CitizenTabPageState();
}

class _CitizenTabPageState extends State<CitizenTabPage> {
  int _selectedTab = 0;
  // 提案页回传待投票数，本页只负责同步展示，不复制投票资格或计票逻辑。
  int _pendingVoteCount = 0;
  static const List<String> _tabs = ['提案', '立法', '选举', '治理', '公权'];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _StyledTabs(
            tabs: _tabs,
            selectedIndex: _selectedTab,
            onSelected: (index) {
              setState(() {
                _selectedTab = index;
              });
            },
          ),
          if (_selectedTab == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '提案动态',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: AppLayout.scaled(context, 17),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppLayout.scaled(context, 10),
                      vertical: AppLayout.scaled(context, 5),
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(10),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(color: AppTheme.primary),
                    ),
                    child: Text(
                      '待我投票 $_pendingVoteCount',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: AppLayout.scaled(context, 12),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildTabContent()),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 0: // 提案:全局治理提案流。
        return widget.proposalContent ??
            ProposalTab(onPendingVoteCountChanged: _onPendingVoteCountChanged);
      case 1: // 立法(P3 接法律浏览)
        return const LegislationTab();
      case 2: // 选举(P8 接选举活动视图)
        return const ElectionTab();
      case 3: // 治理:国家储委会/省储委会/省储行(统一目录按机构码过滤)
        return const GovernanceTab();
      case 4: // 公权:全部机构地理浏览
        return const PublicTab();
      default:
        return const SizedBox.shrink();
    }
  }

  void _onPendingVoteCountChanged(int count) {
    widget.onPendingVoteCountChanged?.call(count);
    if (!mounted || count == _pendingVoteCount) return;
    setState(() => _pendingVoteCount = count);
  }
}

/// 公民域二级 tab 切换组件。
class _StyledTabs extends StatelessWidget {
  const _StyledTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      // 删除重复页面标题后，二级导航顶边对齐原标题文字的起始位置。
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: EdgeInsets.all(AppLayout.scaled(context, 4)),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          for (int i = 0; i < tabs.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  padding: EdgeInsets.symmetric(
                    vertical: AppLayout.scaled(context, 8),
                  ),
                  decoration: BoxDecoration(
                    color: i == selectedIndex
                        ? AppTheme.surfaceCard
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    boxShadow: i == selectedIndex
                        ? [
                            BoxShadow(
                              color: AppTheme.primary.withAlpha(15),
                              blurRadius: AppLayout.scaled(context, 4),
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    tabs[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 15),
                      fontWeight: i == selectedIndex
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: i == selectedIndex
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
