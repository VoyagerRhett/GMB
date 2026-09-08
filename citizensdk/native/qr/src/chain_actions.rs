//! CitizenSDK 可处理的 `chain_call` 动作闭集。
//!
//! 数值来自 CitizenChain QR action registry 的 `kind: chain_call` 条目。本文件是
//! CitizenSDK 发布包内的只读投影；SDK 不修改、不运行时读取上游仓库，也不接受未登记动作。

/// 判断 QR 动作是否为已登记的 CitizenChain 调用。
pub const fn is_registered_chain_action(action: u16) -> bool {
    matches!(
        action,
        0x0400
            | 0x0700
            | 0x0701
            | 0x0800
            | 0x0903
            | 0x0904
            | 0x0905
            | 0x0a00
            | 0x0a01
            | 0x0a02
            | 0x0a03
            | 0x0a04
            | 0x0a06
            | 0x0a07
            | 0x0a08
            | 0x0c00
            | 0x0c02
            | 0x0d00
            | 0x0f00
            | 0x0f01
            | 0x1100
            | 0x1101
            | 0x1102
            | 0x131e
            | 0x131f
            | 0x1320
            | 0x1321
            | 0x1328
            | 0x1332
            | 0x1333
            | 0x1334
            | 0x1400
            | 0x1500
            | 0x1501
            | 0x1602
            | 0x1603
            | 0x1700
            | 0x1701
            | 0x1702
            | 0x1703
            | 0x1704
            | 0x170a
            | 0x170b
            | 0x170c
            | 0x170d
            | 0x170e
            | 0x1900
            | 0x1901
            | 0x1902
            | 0x1a01
            | 0x1a02
            | 0x1a03
            | 0x1a04
            | 0x1a05
            | 0x1d00
            | 0x1e01
            | 0x1e06
            | 0x1e07
            | 0x1e08
            | 0x1e09
            | 0x1f01
            | 0x1f06
            | 0x1f07
            | 0x1f08
            | 0x1f09
            | 0x2100
            | 0x2101
            | 0x2102
            | 0x2103
            | 0x2104
            | 0x2200
            | 0x2201
            | 0x2202
            | 0x2203
            | 0x2204
            | 0x2205
            | 0x2206
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_unregistered_and_non_chain_actions() {
        assert!(is_registered_chain_action(0x0400));
        assert!(is_registered_chain_action(0x2206));
        assert!(!is_registered_chain_action(1));
        assert!(!is_registered_chain_action(0x1e05));
        assert!(!is_registered_chain_action(0xffff));
    }
}
