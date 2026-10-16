import Foundation

// 本文件由 tools/extract_brand_palette.py 从各品牌官方图标提取，请勿手改。
// 换图标后重跑脚本即可刷新。

/// 各品牌官方图标的主色调色板。
///
/// 用途：详情页卡片的「品牌色磨砂玻璃」底 —— 淘宝橙、星巴克绿、抖音黑，
/// 一律跟着各自的官方图标走，而不是另配一套颜色。
enum BrandPalette {

    /// 键 = Asset 资源名，值 = 主色（按占比降序，最多 3 个）
    static let table: [String: [UInt32]] = [
        "brand-amazon": [0xDCB678, 0x74BEC9, 0x47787D],
        "brand-anneng": [0x000000, 0xC9B073, 0x4A4741],
        "brand-baishi": [0x6F132A, 0xD8CDC1, 0x837476],
        "brand-cainiao": [0x006EFF, 0x000000, 0x9AE5E4],
        "brand-deppon": [0x073E84, 0xF0E038, 0x63726E],
        "brand-dewu": [0x000000, 0x343434, 0xC1C1C1],
        "brand-dhl": [0xFFCC01, 0xDD2923],
        "brand-douyin": [0x0B0B16, 0x8B4B5E, 0x77F3F0],
        "brand-ems": [0x3275B6, 0xD8C6AD, 0xFFFFFF],
        "brand-fangha": [0x050507, 0xFF4B01, 0x6A2911],
        "brand-fengchao": [0xF3C50D, 0x010100, 0xF8D235],
        "brand-guojizhuanyun": [0xFF9B15, 0x012C67, 0xF7F5F2],
        "brand-huolala": [0xFF6600, 0xFFB381, 0xFFFFFF],
        "brand-jd-express": [0xF72324, 0xE49E68, 0xF9F7E2],
        "brand-jd-miaosong": [0xD29247, 0x8D4D23, 0xECD2B6],
        "brand-jd": [0xFA0357, 0xF2E1EF, 0xBE335E],
        "brand-jinlinbao": [0xEEBA4D, 0xF4DCA6, 0xFFFFFF],
        "brand-kuaibao": [0x27CC6E, 0x84DFAD, 0xFFFFFF],
        "brand-linli": [0xD61335, 0xFCF8F9],
        "brand-luckin": [0x162991, 0x528FE1, 0xB5D0F2],
        "brand-mama": [0xFF7B23, 0xFFFFFF],
        "brand-meituan": [0xFFE41F, 0x000000, 0x978812],
        "brand-mixue": [0xE60012, 0xD9D2C9],
        "brand-niaoxiang": [0xFCB50D, 0xBE924B, 0x632718],
        "brand-pinduoduo": [0xF40009, 0xF96E72, 0xFEE5E6],
        "brand-railway12306": [0x1A85F3, 0x18C5FB, 0xEB0C11],
        "brand-shentong": [0xFF6700, 0x5E5C5D, 0xDF9F77],
        "brand-shunfeng": [0x000000, 0x322222, 0xADAAAB],
        "brand-starbucks": [0x00A862, 0x67CBA1, 0xFDFEFD],
        "brand-taobao-shangou": [0x0BB5F9, 0xFF760B, 0xFF4A00],
        "brand-taobao": [0xFC5900, 0xFEC69A, 0xFFFFF2],
        "brand-tiantian": [0x24AAE2, 0xA4D5ED, 0x2569AD],
        "brand-tmall": [0xFF0036, 0x000000, 0xF3D5DB],
        "brand-tuxi": [0x363AFB, 0x6257D9, 0xFFFFFF],
        "brand-xianyu": [0xFDFA01, 0x886A14, 0xFEFD8F],
        "brand-xiaobing": [0x399339, 0x69AB68, 0xF5F9F5],
        "brand-xiaohongshu": [0xFF2442, 0xFF5C72, 0xFFFFFF],
        "brand-xintian": [0xFF7701, 0xFBE7D5, 0xFFFFFF],
        "brand-xiongmao": [0xED6D00, 0x010101, 0x974A0F],
        "brand-yishoufa": [0xF5B918, 0x233649, 0xF4E3AC],
        "brand-yousu": [0x322648, 0xDDBE82, 0x887D86],
        "brand-yuantong": [0x4D148C, 0x94437E, 0xFFFFFF],
        "brand-yunda": [0xFABF01, 0x050400, 0xA17C02],
        "brand-zhaijisong": [0x6BA381, 0xCADAD1, 0x3F3B39],
        "brand-zhongtie": [0x2C4773, 0xC5CDD6, 0xEDEEEE],
        "brand-zhongtong": [0x3377F6, 0xD9E4F8, 0x6999F1],
        "brand-zhuanzhuan": [0xFF0D25, 0xFFEEDB, 0xCA4E56],
    ]

    /// 取某个品牌图标的调色板；未收录返回 nil，由调用方回落到品牌主色。
    static func colors(forAsset asset: String?) -> [UInt32]? {
        guard let asset, let value = table[asset], !value.isEmpty else { return nil }
        return value
    }
}
