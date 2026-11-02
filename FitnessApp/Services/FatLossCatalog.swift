import Foundation

/// Original cooking combinations. Reference amounts describe a two-portion batch, not a medical prescription.
enum FatLossCatalog {
    static let guidance = "七组双日午晚餐与四款早餐轮换。每张卡为两份烹饪示例，个人主食和蛋白食物量待医生/营养师确认；营养未核算。吃完再记录实际份数，不把计划当成已吃。"
    static let jumpRopeGuidance = "每周二、周日各一次，下午或晚上分段完成。周二 10 轮 60 秒跳／60 秒休；周日 10 轮 50 秒跳／70 秒休。分别记录有效跳跃和含休息总时长；下肢疲劳明显或足踝、膝部不适时改低冲击单车。"
    static let coordinationGuidance = "腿部训练先做 3×3 低疲劳箱跳；每次落地稳定、不过度追求高度。动作质量下降或下肢不适时省略。"
    static let storageGuidance = "熟食分浅盒尽快降温，2小时内冷藏到≤4°C；环境>32°C时1小时内。米饭尽量1小时内冷却入冷藏或冷冻，冷藏米饭24小时内吃完，第2天份及时冷冻；其他本轮菜48小时内吃完。带饭用冰袋，到公司立即冷藏。只取当餐份复热一次，中心≥74°C且通体热透；微波中途翻拌。无法确认冷链或存放过久就丢弃。"
    static let sources: [RecipeSource] = [
        .init(title: "曼食慢语：作者自述确认的小红书名称", url: "https://podcasts.apple.com/nl/podcast/amanda%E4%B8%A8%E6%85%A2%E8%AF%AD/id6787959697", verification: "作者播客简介自述小红书名；仅备餐方法线索，本菜单不是该博主原配方，未核验营养"),
        .init(title: "USDA 熟食保存与复热", url: "https://www.fsis.usda.gov/food-safety/safe-food-handling-and-preparation/food-safety-basics/leftovers-and-food-safety", verification: "官方安全指南；已查阅保存温度、冷却时限与复热温度"),
        .init(title: "FSA 剩饭与烹饪安全", url: "https://www.food.gov.uk/safety-hygiene/cooking-your-food", verification: "官方指南；复热一次、充分热透，米饭另按更短保存规则")
    ]
    static let creatorCandidates: [RecipeSource] = [
        .init(title: "贝果儿姑娘：待核验的小红书候选", url: "https://toobigdata.com/red/105438987/", verification: "仅第三方目录，未核验小红书原页与跨平台归属；不作健康背书"),
        .init(title: "日食记：待核验的小红书候选", url: "https://www.newrank.cn/ranklist/xiaohongshu/6/1/2025-07-03", verification: "仅2025年历史第三方榜单，未核验小红书原页；不作健康背书")
    ]

    static func recipe(dayIndex: Int, mealType: MealType) -> RecipeDraft? {
        guard dayIndex >= 0 else { return nil }
        let cycle = dayIndex % 14
        let key: String
        switch mealType {
        case .breakfast: key = "breakfast-\(cycle % 4)"
        case .lunch: key = "lunch-\(cycle / 2)"
        case .dinner: key = "dinner-\(cycle / 2)"
        case .snack: return nil
        }
        return recipes.first { $0.key == key }
    }

    static let recipes: [RecipeDraft] = [
        .init(key: "breakfast-0", title: "小馒头＋蒸蛋", ingredients: [
            .init(name: "小馒头", amountText: "小个2个；约数，两份烹饪参考，个人主食量待调整", referenceGrams: 100),
            .init(name: "鸡蛋", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "温水", amountText: "蛋液体积约1–1.5倍，随确认蛋量调整"),
            .init(name: "生抽", amountText: "5 mL量勺半勺；整批两份合计，可不用"),
        ], steps: ["鸡蛋按确认量打散，加入温水拌匀，分成两个蒸碗。", "蒸锅上汽后加盖蒸至中心完全凝固，时间随碗大小调整，不做半熟蛋羹。", "馒头同时蒸透；按一份馒头、一份蛋羹分盒。次日份及时冷藏，再充分复热。"], equipment: ["蒸锅", "蒸碗2只", "5 mL量勺"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 20,
        storageNote: storageGuidance, substitutions: ["馒头可换软米饭；主食份量另行调整。", "蛋羹不适合时由医生确认其他蛋白食物及量，不自行加蛋白粉。"], sources: sources),
        .init(key: "breakfast-1", title: "吐司＋原味奶制品", ingredients: [
            .init(name: "原味吐司", amountText: "薄片4片；约数，两份参考，个人主食量待调整", referenceGrams: 100),
            .init(name: "原味牛奶或无糖酸奶", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
        ], steps: ["吐司按确认的主食份量分两份，食用前可烤或蒸热，不额外抹黄油或甜酱。", "牛奶或酸奶二选一，按医生/营养师确认量单独取出；奶制品依包装冷藏。", "牛奶可单独温热；酸奶不混入需要存两天的其他熟食。只取当餐份，不反复加热整瓶。"], equipment: ["烤面包机或蒸锅", "奶杯"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 10,
        storageNote: storageGuidance, substitutions: ["奶制品二选一，不默认叠加；如出现不耐受，记录后再确认替代。", "吐司可换小馒头，但实际份量与营养不能按片数自动等同。"], sources: sources),
        .init(key: "breakfast-2", title: "米粥＋全熟鸡蛋＋熟蔬菜", ingredients: [
            .init(name: "生大米", amountText: "平汤匙约6匙；煮粥用；两份烹饪参考，个人主食量待整体菜单确认", referenceGrams: 60),
            .init(name: "鸡蛋", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "小白菜", amountText: "小把2把；约数，按实际大小调整", referenceGrams: 200),
            .init(name: "清水", amountText: "约800 mL，按粥的稠度调整"),
            .init(name: "食用油", amountText: "5 mL量勺1勺；整批两份合计"),
        ], steps: ["大米加水煮开后转小火，煮至熟软；鸡蛋按确认数量煮至蛋白蛋黄均凝固。", "小白菜洗净切细，加量好的油和少量水煮熟。", "粥、鸡蛋、熟菜分装两份。冷藏米粥24小时内吃完，稍晚的第二天份尽快冷冻；鸡蛋复热前剥壳。"], equipment: ["小锅2口", "炒锅", "5 mL量勺"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 30,
        storageNote: storageGuidance, substitutions: ["小白菜可换菜心，切细煮软。", "粥不额外加肉松、咸菜；若要替换主食，按已确认份量调整。"], sources: sources),
        .init(key: "breakfast-3", title: "清汤鸡蛋面", ingredients: [
            .init(name: "干面条", amountText: "两小把；两份烹饪参考，个人主食量待调整", referenceGrams: 120),
            .init(name: "鸡蛋", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "小白菜", amountText: "小把2把；约数，按实际大小调整", referenceGrams: 200),
            .init(name: "清水", amountText: "约800 mL"),
            .init(name: "食用油", amountText: "5 mL量勺1勺；整批两份合计"),
            .init(name: "生抽", amountText: "5 mL量勺1勺；整批两份合计，可不用"),
        ], steps: ["将小白菜洗净切段。用清水煮面，按包装时间煮至熟。", "鸡蛋按确认量打散加入，煮至完全凝固，再加菜煮熟。", "用量好的油、生抽调味，分为两份。隔天早餐优先提前分好原料、当天现煮；已经煮好的按共通规则冷藏复热。"], equipment: ["小锅", "5 mL量勺"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 15,
        storageNote: storageGuidance, substitutions: ["面条可换米粉，按包装调整时间与主食份量。", "汤底用清水，不以浓肉汤或火锅底料代替。"], sources: sources),
        .init(key: "lunch-0", title: "姜葱鸡片＋清炒冬瓜＋米饭", ingredients: [
            .init(name: "生大米", amountText: "量米杯约1杯（150 mL）；两份烹饪参考，个人主食量待整体菜单确认", referenceGrams: 120),
            .init(name: "去皮鸡肉", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "冬瓜", amountText: "去皮中碗2碗；约数，按实际大小调整", referenceGrams: 500),
            .init(name: "食用油", amountText: "5 mL量勺2勺；整批两份合计"),
            .init(name: "生抽", amountText: "5 mL量勺1勺；整批两份合计，可不用，不另叠加盐和其他酱料"),
            .init(name: "姜葱蒜", amountText: "姜2片、葱1根或蒜2瓣；按菜式选用"),
        ], steps: ["大米煮饭。鸡肉按确认量切片，冬瓜去皮切薄片；生肉与熟食砧板分开。", "用1勺油炒香姜葱，加入鸡片炒透，可加少量水加盖，禽肉中心至少74°C。", "另1勺油炒冬瓜，加少量清水焖软；将生抽在两道菜中分配，不另加浓汤。", "鸡片、冬瓜和米饭按两份分盒；稍晚的第2天米饭份尽快冷冻。"], equipment: ["电饭煲", "蒸锅或炒锅", "5 mL量勺", "带盖浅盒"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 30,
        storageNote: storageGuidance, substitutions: ["蔬菜可在相近口感的熟蔬菜之间替换，按实际记录；主食和蛋白食物量仍按医生/营养师确认。", "辣椒另装；吃后不适时去辣、切细或煮软，并记录腹胀情况。"], sources: sources),
        .init(key: "dinner-0", title: "番茄蒸蛋＋菜心＋米饭", ingredients: [
            .init(name: "生大米", amountText: "量米杯约1杯（150 mL）；两份烹饪参考，个人主食量待整体菜单确认", referenceGrams: 120),
            .init(name: "鸡蛋", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "番茄", amountText: "中个1个；约数，按实际大小调整", referenceGrams: 150),
            .init(name: "菜心", amountText: "小把2把；约数，按实际大小调整", referenceGrams: 300),
            .init(name: "温水", amountText: "蛋液体积约1–1.5倍，随确认蛋量调整"),
            .init(name: "食用油", amountText: "5 mL量勺2勺；整批两份合计"),
            .init(name: "生抽", amountText: "5 mL量勺1勺；整批两份合计，可不用，不另叠加盐和其他酱料"),
            .init(name: "姜葱蒜", amountText: "姜2片、葱1根或蒜2瓣；按菜式选用"),
        ], steps: ["米饭煮熟，番茄切小丁；鸡蛋按确认量打散，加温水和番茄拌匀。", "分两个小碗加盖蒸至中心完全凝固，不做半熟蛋羹。", "量好的油炒蒜后加入菜心，少量水炒熟，生抽按整批总量分配。", "蛋羹、菜心和米饭分盒，避免菜汁泡饭影响复热。"], equipment: ["电饭煲", "蒸锅或炒锅", "5 mL量勺", "带盖浅盒"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 30,
        storageNote: storageGuidance, substitutions: ["蔬菜可在相近口感的熟蔬菜之间替换，按实际记录；主食和蛋白食物量仍按医生/营养师确认。", "辣椒另装；吃后不适时去辣、切细或煮软，并记录腹胀情况。"], sources: sources),
        .init(key: "lunch-1", title: "彩椒瘦肉丝＋西葫芦＋米饭", ingredients: [
            .init(name: "生大米", amountText: "量米杯约1杯（150 mL）；两份烹饪参考，个人主食量待整体菜单确认", referenceGrams: 120),
            .init(name: "瘦猪肉", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "彩椒", amountText: "中个2个；约数，按实际大小调整", referenceGrams: 250),
            .init(name: "西葫芦", amountText: "中个1根；约数，按实际大小调整", referenceGrams: 300),
            .init(name: "玉米淀粉", amountText: "5 mL量勺1平勺；整批两份肉丝薄挂浆"),
            .init(name: "食用油", amountText: "5 mL量勺2勺；整批两份合计"),
            .init(name: "生抽", amountText: "5 mL量勺1勺；整批两份合计，可不用，不另叠加盐和其他酱料"),
            .init(name: "姜葱蒜", amountText: "姜2片、葱1根或蒜2瓣；按菜式选用"),
        ], steps: ["米饭煮熟。瘦肉按确认量切丝，用淀粉和少量水薄挂浆；彩椒切条，西葫芦切片。", "用1勺油炒姜、肉丝至完全熟，再放彩椒炒软，生抽调味。", "另1勺油炒西葫芦，加少量水炒至熟软。", "分装两份，肉丝不随意加量，也不靠糖或额外油增加下饭程度。"], equipment: ["电饭煲", "蒸锅或炒锅", "5 mL量勺", "带盖浅盒"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 30,
        storageNote: storageGuidance, substitutions: ["蔬菜可在相近口感的熟蔬菜之间替换，按实际记录；主食和蛋白食物量仍按医生/营养师确认。", "辣椒另装；吃后不适时去辣、切细或煮软，并记录腹胀情况。"], sources: sources),
        .init(key: "dinner-1", title: "家常豆腐＋油麦菜＋米饭", ingredients: [
            .init(name: "生大米", amountText: "量米杯约1杯（150 mL）；两份烹饪参考，个人主食量待整体菜单确认", referenceGrams: 120),
            .init(name: "豆腐", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "胡萝卜", amountText: "小根1根；约数，按实际大小调整", referenceGrams: 100),
            .init(name: "油麦菜", amountText: "小把2把；约数，按实际大小调整", referenceGrams: 300),
            .init(name: "食用油", amountText: "5 mL量勺2勺；整批两份合计"),
            .init(name: "生抽", amountText: "5 mL量勺1勺；整批两份合计，可不用，不另叠加盐和其他酱料"),
            .init(name: "姜葱蒜", amountText: "姜2片、葱1根或蒜2瓣；按菜式选用"),
        ], steps: ["大米煮饭；豆腐按确认量切块，胡萝卜切薄片。", "用1勺油炒姜、胡萝卜，加豆腐和少量水焖透，不先油炸。", "另1勺油炒油麦菜至熟，生抽按整批量分配。", "豆腐和青菜分成两盒，米饭另装。"], equipment: ["电饭煲", "蒸锅或炒锅", "5 mL量勺", "带盖浅盒"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 30,
        storageNote: storageGuidance, substitutions: ["蔬菜可在相近口感的熟蔬菜之间替换，按实际记录；主食和蛋白食物量仍按医生/营养师确认。", "辣椒另装；吃后不适时去辣、切细或煮软，并记录腹胀情况。"], sources: sources),
        .init(key: "lunch-2", title: "清蒸鱼＋胡萝卜炒丝瓜＋米饭", ingredients: [
            .init(name: "生大米", amountText: "量米杯约1杯（150 mL）；两份烹饪参考，个人主食量待整体菜单确认", referenceGrams: 120),
            .init(name: "去骨鱼肉", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "胡萝卜", amountText: "中根1根；约数，按实际大小调整", referenceGrams: 150),
            .init(name: "丝瓜", amountText: "中等1根；约数，按实际大小调整", referenceGrams: 300),
            .init(name: "食用油", amountText: "5 mL量勺2勺；整批两份合计"),
            .init(name: "生抽", amountText: "5 mL量勺1勺；整批两份合计，可不用，不另叠加盐和其他酱料"),
            .init(name: "姜葱蒜", amountText: "姜2片、葱1根或蒜2瓣；按菜式选用"),
        ], steps: ["大米煮饭，鱼肉按确认量加姜丝放蒸盘；胡萝卜切薄片，丝瓜去皮切片。", "鱼肉蒸至完全熟透，按鱼肉厚度调整时间，仔细挑净鱼刺。", "用量好的油先炒胡萝卜，加少量水焖软，再放丝瓜炒熟，以生抽调味。", "鱼优先当日吃；第二天份可提前分好生料冷冻后翌日现蒸，或熟后及时冷冻再按安全规则复热。"], equipment: ["电饭煲", "蒸锅或炒锅", "5 mL量勺", "带盖浅盒"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 30,
        storageNote: storageGuidance, substitutions: ["蔬菜可在相近口感的熟蔬菜之间替换，按实际记录；主食和蛋白食物量仍按医生/营养师确认。", "辣椒另装；吃后不适时去辣、切细或煮软，并记录腹胀情况。"], sources: sources),
        .init(key: "dinner-2", title: "青菜鸡蛋面", ingredients: [
            .init(name: "干面条", amountText: "两小把；两份烹饪参考，个人主食量待调整", referenceGrams: 140),
            .init(name: "鸡蛋", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "小白菜", amountText: "小把2把；约数，按实际大小调整", referenceGrams: 300),
            .init(name: "胡萝卜", amountText: "小根1根；约数，按实际大小调整", referenceGrams: 100),
            .init(name: "清水", amountText: "约900 mL，随面条和喜欢的汤量调整"),
            .init(name: "食用油", amountText: "5 mL量勺1勺；整批两份合计"),
            .init(name: "生抽", amountText: "5 mL量勺1勺；整批两份合计，可不用，不另叠加盐和其他酱料"),
            .init(name: "姜葱蒜", amountText: "姜2片、葱1根或蒜2瓣；按菜式选用"),
        ], steps: ["小白菜和胡萝卜洗净切细。清水煮开，先放胡萝卜，再下面条，按包装时间煮熟。", "鸡蛋按确认量打散加入，煮至完全凝固，再加入青菜煮熟。", "油、生抽按总量调味，不另加浓肉汤或加工肉。", "两份面和汤尽量分盒；复热中途搅拌。口感更佳的做法是预备原料，第二天现煮。"], equipment: ["小锅", "5 mL量勺", "带盖浅盒"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 20,
        storageNote: storageGuidance, substitutions: ["蔬菜可在相近口感的熟蔬菜之间替换，按实际记录；主食和蛋白食物量仍按医生/营养师确认。", "辣椒另装；吃后不适时去辣、切细或煮软，并记录腹胀情况。"], sources: sources),
        .init(key: "lunch-3", title: "土豆焖去皮鸡＋菜心", ingredients: [
            .init(name: "土豆", amountText: "中个2个；本餐主食参考，个人总量待调整；约数，按实际大小调整", referenceGrams: 400),
            .init(name: "去皮鸡肉", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "菜心", amountText: "小把2把；约数，按实际大小调整", referenceGrams: 300),
            .init(name: "食用油", amountText: "5 mL量勺2勺；整批两份合计"),
            .init(name: "生抽", amountText: "5 mL量勺1勺；整批两份合计，可不用，不另叠加盐和其他酱料"),
            .init(name: "姜葱蒜", amountText: "姜2片、葱1根或蒜2瓣；按菜式选用"),
        ], steps: ["土豆去皮切薄块，鸡肉按确认量切块；另洗净菜心。", "用1勺油炒姜葱和鸡肉，加土豆与少量清水加盖焖，至土豆熟软、禽肉中心至少74°C。", "另1勺油炒菜心至熟，生抽按整批量分配。", "土豆作为本卡主食部分，两份分装；若要另配米饭需调整整体主食份量，不能默认叠加。"], equipment: ["炒锅", "食物温度计", "5 mL量勺", "带盖浅盒"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 30,
        storageNote: storageGuidance, substitutions: ["蔬菜可在相近口感的熟蔬菜之间替换，按实际记录；主食和蛋白食物量仍按医生/营养师确认。", "辣椒另装；吃后不适时去辣、切细或煮软，并记录腹胀情况。"], sources: sources),
        .init(key: "dinner-3", title: "番茄豆腐＋西葫芦＋米饭", ingredients: [
            .init(name: "生大米", amountText: "量米杯约1杯（150 mL）；两份烹饪参考，个人主食量待整体菜单确认", referenceGrams: 120),
            .init(name: "豆腐", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "番茄", amountText: "中个2个；约数，按实际大小调整", referenceGrams: 300),
            .init(name: "西葫芦", amountText: "中个1根；约数，按实际大小调整", referenceGrams: 300),
            .init(name: "食用油", amountText: "5 mL量勺2勺；整批两份合计"),
            .init(name: "生抽", amountText: "5 mL量勺1勺；整批两份合计，可不用，不另叠加盐和其他酱料"),
            .init(name: "姜葱蒜", amountText: "姜2片、葱1根或蒜2瓣；按菜式选用"),
        ], steps: ["大米煮饭，番茄切块，豆腐按确认量切块，西葫芦切片。", "1勺油炒番茄出汁，加豆腐和少量水煮透，以生抽调味。", "另1勺油炒西葫芦至熟软。", "分装两份，番茄豆腐汤汁与米饭分开，复热后再搭配。"], equipment: ["电饭煲", "蒸锅或炒锅", "5 mL量勺", "带盖浅盒"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 30,
        storageNote: storageGuidance, substitutions: ["蔬菜可在相近口感的熟蔬菜之间替换，按实际记录；主食和蛋白食物量仍按医生/营养师确认。", "辣椒另装；吃后不适时去辣、切细或煮软，并记录腹胀情况。"], sources: sources),
        .init(key: "lunch-4", title: "番茄瘦肉＋冬瓜＋米饭", ingredients: [
            .init(name: "生大米", amountText: "量米杯约1杯（150 mL）；两份烹饪参考，个人主食量待整体菜单确认", referenceGrams: 120),
            .init(name: "瘦猪肉", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "番茄", amountText: "中个2个；约数，按实际大小调整", referenceGrams: 300),
            .init(name: "冬瓜", amountText: "去皮中碗1碗；约数，按实际大小调整", referenceGrams: 300),
            .init(name: "食用油", amountText: "5 mL量勺2勺；整批两份合计"),
            .init(name: "生抽", amountText: "5 mL量勺1勺；整批两份合计，可不用，不另叠加盐和其他酱料"),
            .init(name: "姜葱蒜", amountText: "姜2片、葱1根或蒜2瓣；按菜式选用"),
        ], steps: ["大米煮饭，瘦肉按确认量切薄片；番茄、冬瓜切片。", "1勺油炒番茄出汁，加入肉片煮至完全熟透，生抽调味。", "另1勺油炒冬瓜后加少量水焖软，不额外煲肉汤。", "分装两份，按盒标注制作时间与个人配量状态。"], equipment: ["电饭煲", "蒸锅或炒锅", "5 mL量勺", "带盖浅盒"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 30,
        storageNote: storageGuidance, substitutions: ["蔬菜可在相近口感的熟蔬菜之间替换，按实际记录；主食和蛋白食物量仍按医生/营养师确认。", "辣椒另装；吃后不适时去辣、切细或煮软，并记录腹胀情况。"], sources: sources),
        .init(key: "dinner-4", title: "丝瓜蒸蛋＋胡萝卜＋米饭", ingredients: [
            .init(name: "生大米", amountText: "量米杯约1杯（150 mL）；两份烹饪参考，个人主食量待整体菜单确认", referenceGrams: 120),
            .init(name: "鸡蛋", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "丝瓜", amountText: "中等1根；约数，按实际大小调整", referenceGrams: 300),
            .init(name: "胡萝卜", amountText: "中根2根；约数，按实际大小调整", referenceGrams: 250),
            .init(name: "温水", amountText: "蛋液体积约1–1.5倍，随确认蛋量调整"),
            .init(name: "食用油", amountText: "5 mL量勺2勺；整批两份合计"),
            .init(name: "生抽", amountText: "5 mL量勺1勺；整批两份合计，可不用，不另叠加盐和其他酱料"),
            .init(name: "姜葱蒜", amountText: "姜2片、葱1根或蒜2瓣；按菜式选用"),
        ], steps: ["大米煮饭，丝瓜去皮切薄片，胡萝卜切片。", "鸡蛋按确认量打散，加温水和丝瓜，分小碗加盖蒸至中心全熟凝固。", "胡萝卜加少量水焖软，拌入量好的油与生抽；调味总量不因分两道菜翻倍。", "蒸蛋与米饭分盒，复热时注意中心温度，不能只热表面。"], equipment: ["电饭煲", "蒸锅或炒锅", "5 mL量勺", "带盖浅盒"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 30,
        storageNote: storageGuidance, substitutions: ["蔬菜可在相近口感的熟蔬菜之间替换，按实际记录；主食和蛋白食物量仍按医生/营养师确认。", "辣椒另装；吃后不适时去辣、切细或煮软，并记录腹胀情况。"], sources: sources),
        .init(key: "lunch-5", title: "姜葱鸡片＋油麦菜＋米饭", ingredients: [
            .init(name: "生大米", amountText: "量米杯约1杯（150 mL）；两份烹饪参考，个人主食量待整体菜单确认", referenceGrams: 120),
            .init(name: "去皮鸡肉", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "油麦菜", amountText: "小把3把；约数，按实际大小调整", referenceGrams: 450),
            .init(name: "食用油", amountText: "5 mL量勺2勺；整批两份合计"),
            .init(name: "生抽", amountText: "5 mL量勺1勺；整批两份合计，可不用，不另叠加盐和其他酱料"),
            .init(name: "姜葱蒜", amountText: "姜2片、葱1根或蒜2瓣；按菜式选用"),
        ], steps: ["大米煮饭，鸡肉按确认量切片，油麦菜洗净切段。", "用1勺油炒姜葱、鸡肉，加少量水加盖炒至熟透，禽肉中心至少74°C。", "另1勺油炒油麦菜至熟软，生抽按两份合计调味。", "两份鸡片、米饭与熟菜分盒；较老菜梗切细。"], equipment: ["电饭煲", "蒸锅或炒锅", "5 mL量勺", "带盖浅盒"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 30,
        storageNote: storageGuidance, substitutions: ["蔬菜可在相近口感的熟蔬菜之间替换，按实际记录；主食和蛋白食物量仍按医生/营养师确认。", "辣椒另装；吃后不适时去辣、切细或煮软，并记录腹胀情况。"], sources: sources),
        .init(key: "dinner-5", title: "豆腐青菜煲＋蒸南瓜及配量主食", ingredients: [
            .init(name: "豆腐", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "小白菜", amountText: "小把2把；约数，按实际大小调整", referenceGrams: 300),
            .init(name: "南瓜", amountText: "去皮中碗1碗；约数，按实际大小调整", referenceGrams: 250),
            .init(name: "生大米", amountText: "量米杯约半杯（75 mL）；与南瓜合并作为主食参考；两份烹饪参考，个人主食量待整体菜单确认", referenceGrams: 60),
            .init(name: "清水", amountText: "约200 mL，用于焖豆腐和青菜"),
            .init(name: "食用油", amountText: "5 mL量勺1勺；整批两份合计"),
            .init(name: "生抽", amountText: "5 mL量勺1勺；整批两份合计，可不用，不另叠加盐和其他酱料"),
            .init(name: "姜葱蒜", amountText: "姜2片、葱1根或蒜2瓣；按菜式选用"),
        ], steps: ["按已确认的总主食量决定米饭与南瓜用量；米饭煮熟，南瓜切块蒸熟。", "豆腐按确认量切块，小白菜切段；用量好的油炒姜，加清水和豆腐煮透。", "放入小白菜煮熟，生抽调味；不另加浓高汤。", "豆腐煲、南瓜与配量主食分两份，汤菜和米饭分开保存。"], equipment: ["电饭煲", "蒸锅或炒锅", "5 mL量勺", "带盖浅盒"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 30,
        storageNote: storageGuidance, substitutions: ["蔬菜可在相近口感的熟蔬菜之间替换，按实际记录；主食和蛋白食物量仍按医生/营养师确认。", "辣椒另装；吃后不适时去辣、切细或煮软，并记录腹胀情况。"], sources: sources),
        .init(key: "lunch-6", title: "肉末蒸蛋＋菜心＋米饭", ingredients: [
            .init(name: "生大米", amountText: "量米杯约1杯（150 mL）；两份烹饪参考，个人主食量待整体菜单确认", referenceGrams: 120),
            .init(name: "瘦猪肉末", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "鸡蛋", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "菜心", amountText: "小把2把；约数，按实际大小调整", referenceGrams: 350),
            .init(name: "温水", amountText: "蛋液体积约1–1.5倍，随确认蛋量调整"),
            .init(name: "食用油", amountText: "5 mL量勺2勺；整批两份合计"),
            .init(name: "生抽", amountText: "5 mL量勺1勺；整批两份合计，可不用，不另叠加盐和其他酱料"),
            .init(name: "姜葱蒜", amountText: "姜2片、葱1根或蒜2瓣；按菜式选用"),
        ], steps: ["大米煮饭；肉末与鸡蛋都按确认量取用，不能只确认肉量后再随意叠加蛋量。", "肉末用少量水打散，与蛋液和温水混合分碗，加盖蒸至中心全熟，肉蛋均无未熟部分。", "菜心洗净，用量好的油炒至熟软，生抽按整批量分配。", "分两份，蒸蛋较厚时延长加热并检查中心，不以表面凝固判断熟透。"], equipment: ["电饭煲", "蒸锅或炒锅", "5 mL量勺", "带盖浅盒"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 30,
        storageNote: storageGuidance, substitutions: ["蔬菜可在相近口感的熟蔬菜之间替换，按实际记录；主食和蛋白食物量仍按医生/营养师确认。", "辣椒另装；吃后不适时去辣、切细或煮软，并记录腹胀情况。"], sources: sources),
        .init(key: "dinner-6", title: "番茄鸡蛋烩饭＋西葫芦", ingredients: [
            .init(name: "生大米", amountText: "量米杯约1杯（150 mL）；两份烹饪参考，个人主食量待整体菜单确认", referenceGrams: 120),
            .init(name: "鸡蛋", amountText: "待医生/营养师确认两份总用量；不要按普通健身餐自行加量", isMedicalPortionPending: true),
            .init(name: "番茄", amountText: "中个2个；约数，按实际大小调整", referenceGrams: 300),
            .init(name: "西葫芦", amountText: "中个1根；约数，按实际大小调整", referenceGrams: 300),
            .init(name: "食用油", amountText: "5 mL量勺2勺；整批两份合计"),
            .init(name: "生抽", amountText: "5 mL量勺1勺；整批两份合计，可不用，不另叠加盐和其他酱料"),
            .init(name: "姜葱蒜", amountText: "姜2片、葱1根或蒜2瓣；按菜式选用"),
        ], steps: ["米饭煮熟；番茄切块，西葫芦切片，鸡蛋按确认量打散。", "用1勺油炒番茄出汁，倒入蛋液炒至完全凝固；吃时再与米饭烩匀。", "另1勺油炒西葫芦至熟，以量好的生抽调味。", "备餐时番茄蛋与米饭分盒；米饭稍晚的第2天份及时冷冻，当餐充分复热后组合。"], equipment: ["电饭煲", "蒸锅或炒锅", "5 mL量勺", "带盖浅盒"],
        householdPortion: "两份烹饪示例；每盒=1份。参考量不是个人处方，肉蛋奶豆待医生配量。", portions: 2, cookingMinutes: 30,
        storageNote: storageGuidance, substitutions: ["蔬菜可在相近口感的熟蔬菜之间替换，按实际记录；主食和蛋白食物量仍按医生/营养师确认。", "辣椒另装；吃后不适时去辣、切细或煮软，并记录腹胀情况。"], sources: sources),
    ]

    static let trainingGuidance = "每次聚焦 1–2 个肌群，热身后完成计划工作组。复合动作通常保留约 2–3 RIR，孤立动作最后一组可到约 1–2 RIR；动作质量下降时不追加容量。连续两次达到次数上限且恢复正常，再手动增加最小一档重量。"
    static let focusedTrainingGuidance = "本次只围绕主肌群和辅助肌群集中训练。复合动作先完成 1 个保留 1–2 RIR 的主组，再做 2–3 个减重工作组；孤立动作最后一组可到 0–1 RIR。热身组不计入有效容量；连续两个动作表现下降超过约 10% 或达到 90 分钟时，停止追加最后的孤立组。"
    static let progressionGuidance = "工作重量优先读取同动作上次完成记录：落在次数区间下限并保留 2–3 RIR。连续两次完成全部组的次数上限、动作稳定且恢复正常，才增加最小一档；未达下限或 RIR≤1 时维持或下调。"
    static let lowEnergyGuidance = "早晨只有咖啡和电解质饮料时，首个复合动作先比上次工作重量低 5%–10%，保留 3–4 RIR；热身后状态正常再小幅回调，不用加组补偿。出现头晕、恶心或明显乏力时停止训练。"

    static func trainingProgram(preference: TrainingPreferenceSnapshot) -> TrainingProgramSnapshot {
        if preference.revisionCode == TrainingPreferenceSnapshot.upperBodyTravelWeek.revisionCode {
            return TrainingProgramSnapshot(code: "CUT-UPPER-TRAVEL-20260921-R1", title: "旅行上肢周 · 胸肩与背腹",
                preferenceRevisionCode: preference.revisionCode,
                strengthWorkouts: upperBodyTravelStrengthWorkouts, cardioWorkouts: upperBodyTravelCardioWorkouts,
                progressionRule: "仅9/21–27；首组 RIR 3，其余 RIR 2–3。当天热身决定重量，不自动填重，不追纪录、力竭或递减组。",
                lowEnergyRule: travelSafetyGuidance)
        }
        if preference.revisionCode == TrainingPreferenceSnapshot.lowerBodySpecialtyWeek.revisionCode {
            return TrainingProgramSnapshot(
                code: "CUT-LB3-20260914-R1",
                title: "下肢专项燃脂周 · 前后链与足踝",
                preferenceRevisionCode: preference.revisionCode,
                strengthWorkouts: lowerBodySpecialtyStrengthWorkouts,
                cardioWorkouts: lowerBodySpecialtyCardioWorkouts,
                progressionRule: "本周优先完成质量与总容量：主项保留 2–3 RIR，辅项保留 1–2 RIR；只在动作稳定且无足踝、膝、腰背异常时增加最小一档重量。",
                lowEnergyRule: lowEnergyGuidance
            )
        }
        if preference.revisionCode == TrainingPreferenceSnapshot.weekdayFocused.revisionCode {
            return TrainingProgramSnapshot(
                code: "CUT-4D-20260908-R2",
                title: "本周过渡 · 周中优先高集中训练",
                preferenceRevisionCode: preference.revisionCode,
                strengthWorkouts: weekdayFocusedStrengthWorkouts,
                cardioWorkouts: weekdayFocusedCardioWorkouts,
                progressionRule: progressionGuidance,
                lowEnergyRule: lowEnergyGuidance
            )
        }
        return TrainingProgramSnapshot(
            code: "CUT-4D-20260908",
            title: "减脂保肌 · 四日部位分化",
            preferenceRevisionCode: preference.revisionCode,
            strengthWorkouts: confirmedStrengthWorkouts,
            cardioWorkouts: confirmedCardioWorkouts.filter {
                $0.code == "ROPE_TUE" ? preference.jumpRopeSessionsPerWeek >= 1
                    : $0.code == "ROPE_SUN" ? preference.jumpRopeSessionsPerWeek >= 2 : preference.zone2SessionsPerWeek >= 1
            }.map { item in
                guard item.code == "ZONE2_FRI" else { return item }
                var updated = item
                updated.activeSeconds = preference.zone2Minutes * 60
                updated.elapsedSeconds = (preference.zone2Minutes + 10) * 60
                updated.intervals = "热身 5 分钟＋稳定 \(preference.zone2Minutes) 分钟＋放松 5 分钟"
                return updated
            },
            progressionRule: progressionGuidance,
            lowEnergyRule: lowEnergyGuidance
        )
    }

    static func workouts(preference: TrainingPreferenceSnapshot) -> [ProgramWorkoutDraft] {
        trainingProgram(preference: preference).strengthWorkouts
    }

    static func cardioWorkouts(preference: TrainingPreferenceSnapshot) -> [ProgramCardioDraft] {
        trainingProgram(preference: preference).cardioWorkouts
    }

    static let travelSafetyGuidance = "先轻松热身5–8分钟，再做首个推／拉递增热身，热身不计工作组。首个工作组 RIR 3，其余 RIR 2–3；复合休息2–3分钟，孤立和核心60–90秒。左肘疼痛、逐组加重或代偿时停止动作；弯举下压可直接省去，不补组。训练后或次晨加重，下次取消直接手臂训练，并减少或暂停诱发不适的推拉。明显无力、麻木、肿热、活动受限时先评估。旅途疲劳或供能不足时减量或休息。"
    private static let travelSetGuidance = "首个工作组 RIR 3，其余 RIR 2–3；重量待当天热身确定，疼痛时停止，不做力竭。"
    static let hotelFallbackGuidance = "有高位下拉时用3组下拉替换胸托哑铃划船；无可调凳用坐姿划船器械替代，两者都没有就省去，不重复堆量。无可用抗阻器械只保留核心和恢复活动，背部标为器械受限未完成；跳绳只替代有氧，不算完成背部力量。"

    private static let upperBodyTravelStrengthWorkouts: [ProgramWorkoutDraft] = [
        .init(code: "TRAVEL_CHEST_A", title: "胸肩 A＋三头 · 旅行周", weekday: 2, exercises: [
            .init(name: "上斜哑铃卧推", muscleGroup: "胸部", equipment: "哑铃", sets: 3, repsLower: 8, repsUpper: 12, restSeconds: 150, note: "低上斜。" + travelSetGuidance),
            .init(name: "器械推胸", muscleGroup: "胸部", equipment: "器械", sets: 3, repsLower: 10, repsUpper: 15, restSeconds: 150, note: "坐姿推胸。" + travelSetGuidance),
            .init(name: "蝴蝶机夹胸", muscleGroup: "胸部", equipment: "器械", sets: 2, repsLower: 12, repsUpper: 20, restSeconds: 75, note: travelSetGuidance),
            .init(name: "器械肩推", muscleGroup: "肩部", equipment: "器械", sets: 2, repsLower: 10, repsUpper: 15, restSeconds: 150, note: "不冲大重量。" + travelSetGuidance),
            .init(name: "绳索侧平举", muscleGroup: "肩部", equipment: "龙门架", sets: 3, repsLower: 15, repsUpper: 20, restSeconds: 75, unilateral: true, note: "可换器械侧平举；绳索每侧完成。" + travelSetGuidance),
            .init(name: "绳索下压", muscleGroup: "手臂", equipment: "龙门架", sets: 2, repsLower: 12, repsUpper: 20, restSeconds: 75, note: "三头仅2组，不额外加双杠或窄握卧推。" + travelSetGuidance)
        ], guidance: "60–75分钟，15个工作组。" + travelSafetyGuidance),
        .init(code: "TRAVEL_BACK_A", title: "背腹 A＋二头 · 旅行周", weekday: 3, exercises: [
            .init(name: "中立握高位下拉", muscleGroup: "背部", equipment: "器械", sets: 3, repsLower: 10, repsUpper: 15, restSeconds: 150, note: "中立握仅为候选，不保证无痛。" + travelSetGuidance),
            .init(name: "胸托划船", muscleGroup: "背部", equipment: "器械或哑铃", sets: 3, repsLower: 10, repsUpper: 15, restSeconds: 150, note: travelSetGuidance),
            .init(name: "单臂绳索划船至髋", muscleGroup: "背部", equipment: "龙门架", sets: 2, repsLower: 12, repsUpper: 15, restSeconds: 120, unilateral: true, note: "每侧完成，肘贴近身体。" + travelSetGuidance),
            .init(name: "绳索弯举", muscleGroup: "手臂", equipment: "龙门架", sets: 2, repsLower: 12, repsUpper: 20, restSeconds: 75, note: travelSetGuidance),
            .init(name: "绳索卷腹", muscleGroup: "核心", equipment: "龙门架", sets: 3, repsLower: 12, repsUpper: 15, restSeconds: 75, note: travelSetGuidance),
            .init(name: "仰卧反向卷腹", muscleGroup: "核心", equipment: "自重", sets: 3, repsLower: 10, repsUpper: 15, restSeconds: 75, volumeUnitRaw: ExerciseVolumeUnit.count.rawValue, note: "不用悬垂抓握。" + travelSetGuidance)
        ], guidance: "60–75分钟，16个工作组；不排重杠铃划船、反握引体或大量弯举。" + travelSafetyGuidance),
        .init(code: "TRAVEL_CHEST_B", title: "胸肩 B＋三头 · 出发前减量", weekday: 4, exercises: [
            .init(name: "器械推胸", muscleGroup: "胸部", equipment: "器械", sets: 3, repsLower: 12, repsUpper: 15, restSeconds: 150, note: travelSetGuidance),
            .init(name: "蝴蝶机夹胸", muscleGroup: "胸部", equipment: "器械", sets: 2, repsLower: 15, repsUpper: 20, restSeconds: 75, note: travelSetGuidance),
            .init(name: "绳索侧平举", muscleGroup: "肩部", equipment: "龙门架", sets: 3, repsLower: 15, repsUpper: 20, restSeconds: 75, unilateral: true, note: "可换器械侧平举。" + travelSetGuidance),
            .init(name: "反向蝴蝶机", muscleGroup: "肩部", equipment: "器械", sets: 2, repsLower: 15, repsUpper: 20, restSeconds: 75, note: travelSetGuidance),
            .init(name: "绳索下压", muscleGroup: "手臂", equipment: "龙门架", sets: 2, repsLower: 15, repsUpper: 20, restSeconds: 75, note: travelSetGuidance)
        ], guidance: "45–60分钟，12个工作组；不做重肩推、不追纪录、不追加收尾，为当晚航班留余力。" + travelSafetyGuidance),
        .init(code: "TRAVEL_BACK_B", title: "酒店背腹 B＋二头 · 旅行周", weekday: 7, exercises: [
            .init(name: "单臂哑铃划船", muscleGroup: "背部", equipment: "哑铃", sets: 3, repsLower: 10, repsUpper: 15, restSeconds: 150, unilateral: true, note: "支撑身体，肘贴近身体，每侧完成。" + travelSetGuidance),
            .init(name: "上斜凳胸托哑铃划船", muscleGroup: "背部", equipment: "哑铃", sets: 3, repsLower: 12, repsUpper: 15, restSeconds: 150, note: hotelFallbackGuidance + travelSetGuidance),
            .init(name: "哑铃反向飞鸟", muscleGroup: "肩部", equipment: "哑铃", sets: 2, repsLower: 15, repsUpper: 20, restSeconds: 75, note: "轻重量。" + travelSetGuidance),
            .init(name: "哑铃弯举", muscleGroup: "手臂", equipment: "哑铃", sets: 2, repsLower: 12, repsUpper: 20, restSeconds: 75, note: "使用舒适握法，可直接省去不补组。" + travelSetGuidance),
            .init(name: "仰卧反向卷腹", muscleGroup: "核心", equipment: "自重", sets: 3, repsLower: 10, repsUpper: 15, restSeconds: 75, volumeUnitRaw: ExerciseVolumeUnit.count.rawValue, note: travelSetGuidance),
            .init(name: "死虫式", muscleGroup: "核心", equipment: "自重", sets: 3, repsLower: 6, repsUpper: 10, restSeconds: 75, volumeUnitRaw: ExerciseVolumeUnit.count.rawValue, unilateral: true, note: "每侧6–10次。" + travelSetGuidance)
        ], guidance: "50–65分钟，16个工作组。" + hotelFallbackGuidance + travelSafetyGuidance)
    ]

    private static let travelCardioGuidance = "能轻松说完整句子的强度；椭圆机不必用力拉推活动把手。无有氧器械且左肘、足踝无不适时，可选8–10轮跳30秒／步行休60秒，不是30分钟单车的等量替换；握绳或转腕不适改步行。跳绳不能替代背部力量。"
    private static let upperBodyTravelCardioWorkouts: [ProgramCardioDraft] = [
        .init(code: "RECOVERY_THU_TRAVEL", title: "恢复单车／椭圆机 · 抵达日", weekday: 5, timing: "按旅途恢复情况", activeSeconds: 1800, elapsedSeconds: 1800, intervals: "最多30分钟；疲劳明显则休息", guidance: travelCardioGuidance),
        .init(code: "RECOVERY_FRI_TRAVEL", title: "恢复单车／椭圆机 · 轻松活动", weekday: 6, timing: "方便时", activeSeconds: 1200, elapsedSeconds: 1800, intervals: "轻松20–30分钟", guidance: travelCardioGuidance)
    ]

    private static let lowerBodySpecialtyStrengthWorkouts: [ProgramWorkoutDraft] = [
        .init(code: "LOWER_FRONT_LB3", title: "下肢前链＋足踝 · 高消耗", weekday: 2, exercises: [
            .init(name: "膝触墙踝背屈", muscleGroup: "小腿", equipment: "墙面", sets: 2, repsLower: 8, repsUpper: 8, restSeconds: 30, volumeUnitRaw: ExerciseVolumeUnit.count.rawValue, unilateral: true, note: "活动度：脚跟全程着地，膝盖沿第二脚趾方向前移；每侧 8 次"),
            .init(name: "前蹲", muscleGroup: "腿部", equipment: "杠铃", sets: 4, repsLower: 5, repsUpper: 8, restSeconds: 150, note: "前链主项，保留 2–3 RIR；动作质量优先"),
            .init(name: "钟摆深蹲", muscleGroup: "腿部", equipment: "器械", sets: 3, repsLower: 8, repsUpper: 10, restSeconds: 120),
            .init(name: "保加利亚分腿蹲", muscleGroup: "腿部", equipment: "哑铃", sets: 3, repsLower: 8, repsUpper: 10, restSeconds: 90, unilateral: true),
            .init(name: "腿屈伸", muscleGroup: "腿部", equipment: "器械", sets: 3, repsLower: 12, repsUpper: 15, restSeconds: 60),
            .init(name: "坐姿比目鱼肌等长", muscleGroup: "小腿", equipment: "器械", sets: 3, repsLower: 30, repsUpper: 45, restSeconds: 45, volumeUnitRaw: ExerciseVolumeUnit.second.rawValue, note: "刚性：中段位保持稳定张力，足弓不塌，疼痛时停止"),
            .init(name: "胫骨前肌抬脚", muscleGroup: "小腿", equipment: "墙面或器械", sets: 2, repsLower: 12, repsUpper: 15, restSeconds: 45, volumeUnitRaw: ExerciseVolumeUnit.count.rawValue),
            .init(name: "农夫走", muscleGroup: "全身", equipment: "哑铃", sets: 6, repsLower: 30, repsUpper: 30, restSeconds: 75, volumeUnitRaw: ExerciseVolumeUnit.meter.rawValue, note: "高消耗收尾；每组 30 米，共 180 米。选择 RPE 7–8 的重量，并在训练备注按每只哑铃记录负重；躯干稳定、步幅自然")
        ], guidance: "先完成踝背屈活动，再进入前链主项。训练段以 RPE 7–8 为上限；农夫走组间休息 60–90 秒。"),
        .init(code: "LOWER_POSTERIOR_LB3", title: "下肢后链＋足踝 · 高消耗", weekday: 4, exercises: [
            .init(name: "负重膝触墙踝背屈", muscleGroup: "小腿", equipment: "哑铃", sets: 2, repsLower: 8, repsUpper: 8, restSeconds: 30, volumeUnitRaw: ExerciseVolumeUnit.count.rawValue, unilateral: true, note: "活动度：轻负重放在膝上，每侧 8 次，脚跟不离地"),
            .init(name: "单脚平衡触地", muscleGroup: "小腿", equipment: "自重", sets: 2, repsLower: 6, repsUpper: 8, restSeconds: 30, volumeUnitRaw: ExerciseVolumeUnit.count.rawValue, unilateral: true, note: "足弓与踝控制；每侧完成"),
            .init(name: "罗马尼亚硬拉", muscleGroup: "臀部", equipment: "杠铃", sets: 3, repsLower: 6, repsUpper: 8, restSeconds: 150, note: "后链主项；髋后移、背部中立，腰背主导时减重或缩短幅度"),
            .init(name: "臀推", muscleGroup: "臀部", equipment: "杠铃或器械", sets: 4, repsLower: 8, repsUpper: 10, restSeconds: 120),
            .init(name: "坐姿腿弯举", muscleGroup: "腿部", equipment: "器械", sets: 4, repsLower: 10, repsUpper: 12, restSeconds: 75),
            .init(name: "反向箭步蹲", muscleGroup: "腿部", equipment: "哑铃", sets: 3, repsLower: 8, repsUpper: 8, restSeconds: 90, unilateral: true),
            .init(name: "站姿提踵", muscleGroup: "小腿", equipment: "器械", sets: 3, repsLower: 8, repsUpper: 10, restSeconds: 60, note: "刚性：快速但受控地上提，顶端稳定，缓慢下放"),
            .init(name: "提踵中段等长", muscleGroup: "小腿", equipment: "器械", sets: 2, repsLower: 25, repsUpper: 35, restSeconds: 45, volumeUnitRaw: ExerciseVolumeUnit.second.rawValue, note: "刚性：中段位保持足弓与跟腱张力；疼痛时停止"),
            .init(name: "椭圆机间歇", muscleGroup: "全身", equipment: "椭圆机", sets: 8, repsLower: 20, repsUpper: 20, restSeconds: 40, volumeUnitRaw: ExerciseVolumeUnit.second.rawValue, note: "8 分钟：20 秒快／40 秒缓；不追求冲刺到动作变形")
        ], guidance: "后链主项保持腰背中立；收尾以呼吸明显加快但动作仍稳定为准。"),
        .init(code: "LOWER_INTEGRATED_LB3", title: "下肢前后链整合＋足踝", weekday: 6, exercises: [
            .init(name: "膝触墙踝背屈", muscleGroup: "小腿", equipment: "墙面", sets: 2, repsLower: 8, repsUpper: 8, restSeconds: 30, volumeUnitRaw: ExerciseVolumeUnit.count.rawValue, unilateral: true, note: "活动度：脚跟全程着地，每侧 8 次"),
            .init(name: "原地踝弹跳", muscleGroup: "小腿", equipment: "自重", sets: 3, repsLower: 15, repsUpper: 15, restSeconds: 45, volumeUnitRaw: ExerciseVolumeUnit.second.rawValue, note: "刚性：低幅度、短触地、安静落地；足踝或膝不适时改为提踵等长"),
            .init(name: "胫骨前肌抬脚", muscleGroup: "小腿", equipment: "墙面或器械", sets: 2, repsLower: 15, repsUpper: 15, restSeconds: 45, volumeUnitRaw: ExerciseVolumeUnit.count.rawValue),
            .init(name: "腿举", muscleGroup: "腿部", equipment: "器械", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 105),
            .init(name: "坐姿腿弯举", muscleGroup: "腿部", equipment: "器械", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 75),
            .init(name: "行走箭步蹲", muscleGroup: "腿部", equipment: "哑铃", sets: 3, repsLower: 10, repsUpper: 10, restSeconds: 90, unilateral: true, note: "每侧 10 次；躯干稳定"),
            .init(name: "绳索髋后拉", muscleGroup: "臀部", equipment: "龙门架", sets: 3, repsLower: 12, repsUpper: 15, restSeconds: 60),
            .init(name: "椭圆机长间歇", muscleGroup: "全身", equipment: "椭圆机", sets: 7, repsLower: 40, repsUpper: 40, restSeconds: 50, volumeUnitRaw: ExerciseVolumeUnit.second.rawValue, note: "约 10 分钟：40 秒快／50 秒缓；动作质量下降时提前结束")
        ], guidance: "整合日前后链均衡，低幅度踝弹跳只在无疼痛、无肿胀、落地稳定时完成。")
    ]

    private static let lowerBodySpecialtyCardioWorkouts: [ProgramCardioDraft] = [
        .init(code: "ROPE_TUE_LB3", title: "跳绳间歇 · 技术与燃脂", weekday: 3, timing: "下午或晚上", activeSeconds: 600, elapsedSeconds: 1050, intervals: "10 轮：跳 60 秒／休 45 秒；状态良好可加 4 轮 20 秒跳／40 秒休", guidance: "主训练保持 RPE 6–7：呼吸加快但仍能说短句，结束后感觉还能继续约 3–4 分钟。足踝或膝不适时停止并改低冲击单车或椭圆机。"),
        .init(code: "ROPE_SAT_LB3", title: "跳绳混合间歇 · 燃脂", weekday: 7, timing: "下午或晚上", activeSeconds: 720, elapsedSeconds: 1440, intervals: "6 轮：跳 90 秒／休 60 秒；再做 6 轮：跳 30 秒／休 30 秒", guidance: "主训练保持 RPE 6–7：呼吸加快但仍能说短句，结束后感觉还能继续约 3–4 分钟。若周五下肢仍明显疲劳或落地不稳，改为低冲击单车或椭圆机。")
    ]

    private static let confirmedStrengthWorkouts: [ProgramWorkoutDraft] = [
        .init(code: "CHEST_TRI", title: "胸部＋三头", weekday: 3, exercises: [
            .init(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃", sets: 4, repsLower: 6, repsUpper: 8, restSeconds: 180, note: "以同动作上次记录定重量，保留 2–3 RIR；低能量晨练按规则先减 5%–10%"),
            .init(name: "上斜哑铃卧推", muscleGroup: "胸部", equipment: "哑铃", sets: 4, repsLower: 8, repsUpper: 10, restSeconds: 150),
            .init(name: "器械推胸", muscleGroup: "胸部", equipment: "器械", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 120),
            .init(name: "绳索夹胸", muscleGroup: "胸部", equipment: "龙门架", sets: 3, repsLower: 12, repsUpper: 15, restSeconds: 75),
            .init(name: "绳索过顶臂屈伸", muscleGroup: "手臂", equipment: "龙门架", sets: 4, repsLower: 10, repsUpper: 12, restSeconds: 75),
            .init(name: "绳索下压", muscleGroup: "手臂", equipment: "龙门架", sets: 4, repsLower: 12, repsUpper: 15, restSeconds: 60)
        ], guidance: trainingGuidance),
        .init(code: "BACK_BI", title: "背部＋二头", weekday: 5, exercises: [
            .init(name: "中立握高位下拉", muscleGroup: "背部", equipment: "器械", sets: 4, repsLower: 8, repsUpper: 10, restSeconds: 150),
            .init(name: "胸托划船", muscleGroup: "背部", equipment: "器械或哑铃", sets: 4, repsLower: 8, repsUpper: 10, restSeconds: 150),
            .init(name: "单臂绳索划船至髋", muscleGroup: "背部", equipment: "龙门架", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 90, unilateral: true),
            .init(name: "宽握坐姿划船", muscleGroup: "背部", equipment: "器械", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 120),
            .init(name: "上斜哑铃弯举", muscleGroup: "手臂", equipment: "哑铃", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 75),
            .init(name: "牧师凳弯举", muscleGroup: "手臂", equipment: "器械或曲杆", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 75),
            .init(name: "锤式弯举", muscleGroup: "手臂", equipment: "哑铃", sets: 3, repsLower: 12, repsUpper: 15, restSeconds: 60)
        ], guidance: trainingGuidance),
        .init(code: "LEGS_CORE", title: "腿部＋核心", weekday: 7, exercises: [
            .init(name: "箱跳", muscleGroup: "腿部", equipment: "跳箱", sets: 3, repsLower: 3, repsUpper: 3, restSeconds: 90, volumeUnitRaw: ExerciseVolumeUnit.count.rawValue, note: "每次稳定落地；动作质量下降或下肢不适时省略"),
            .init(name: "前蹲", muscleGroup: "腿部", equipment: "杠铃", sets: 4, repsLower: 5, repsUpper: 8, restSeconds: 180, note: "保留 2–3 RIR；不使用 15 次高次数硬撑"),
            .init(name: "罗马尼亚硬拉", muscleGroup: "臀部", equipment: "杠铃", sets: 3, repsLower: 6, repsUpper: 8, restSeconds: 180, note: "髋后移、背部中立；腰背主导时立即减重或缩短幅度"),
            .init(name: "钟摆深蹲", muscleGroup: "腿部", equipment: "器械", sets: 4, repsLower: 8, repsUpper: 12, restSeconds: 150),
            .init(name: "保加利亚分腿蹲", muscleGroup: "腿部", equipment: "哑铃", sets: 3, repsLower: 8, repsUpper: 10, restSeconds: 120, unilateral: true),
            .init(name: "坐姿腿弯举", muscleGroup: "腿部", equipment: "器械", sets: 4, repsLower: 10, repsUpper: 15, restSeconds: 90),
            .init(name: "臀推", muscleGroup: "臀部", equipment: "杠铃或器械", sets: 3, repsLower: 8, repsUpper: 12, restSeconds: 120),
            .init(name: "站姿提踵", muscleGroup: "小腿", equipment: "器械", sets: 3, repsLower: 10, repsUpper: 15, restSeconds: 75),
            .init(name: "抗旋转推", muscleGroup: "核心", equipment: "龙门架", sets: 2, repsLower: 10, repsUpper: 12, restSeconds: 60, unilateral: true),
            .init(name: "绳索躯干旋转", muscleGroup: "核心", equipment: "龙门架", sets: 2, repsLower: 10, repsUpper: 12, restSeconds: 60, unilateral: true)
        ], guidance: trainingGuidance),
        .init(code: "SHOULDERS_ARMS", title: "肩部＋手臂", weekday: 1, exercises: [
            .init(name: "地雷管推举", muscleGroup: "肩部", equipment: "杠铃", sets: 3, repsLower: 8, repsUpper: 10, restSeconds: 120, unilateral: true),
            .init(name: "器械肩推", muscleGroup: "肩部", equipment: "器械", sets: 3, repsLower: 8, repsUpper: 10, restSeconds: 120),
            .init(name: "绳索侧平举", muscleGroup: "肩部", equipment: "龙门架", sets: 5, repsLower: 12, repsUpper: 15, restSeconds: 60, unilateral: true),
            .init(name: "反向蝴蝶机", muscleGroup: "肩部", equipment: "器械", sets: 4, repsLower: 12, repsUpper: 15, restSeconds: 60),
            .init(name: "上斜哑铃弯举", muscleGroup: "手臂", equipment: "哑铃", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 75),
            .init(name: "锤式弯举", muscleGroup: "手臂", equipment: "哑铃", sets: 2, repsLower: 12, repsUpper: 15, restSeconds: 60),
            .init(name: "绳索过顶臂屈伸", muscleGroup: "手臂", equipment: "龙门架", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 75),
            .init(name: "绳索下压", muscleGroup: "手臂", equipment: "龙门架", sets: 2, repsLower: 12, repsUpper: 15, restSeconds: 60)
        ], guidance: trainingGuidance)
    ]

    private static let weekdayFocusedStrengthWorkouts: [ProgramWorkoutDraft] = [
        .init(code: "CHEST_TRI_R2", title: "胸部＋三头 · 当天实际优先", weekday: 3, exercises: [
            .init(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃", sets: 4, repsLower: 6, repsUpper: 8, restSeconds: 180, note: "当天已有手动训练时保留实际记录，不重复导入；递增热身组不计入 4 个工作组"),
            .init(name: "上斜哑铃卧推", muscleGroup: "胸部", equipment: "哑铃", sets: 4, repsLower: 8, repsUpper: 10, restSeconds: 150),
            .init(name: "下斜器械推胸", muscleGroup: "胸部", equipment: "器械", sets: 4, repsLower: 8, repsUpper: 12, restSeconds: 120),
            .init(name: "绳索夹胸", muscleGroup: "胸部", equipment: "龙门架", sets: 4, repsLower: 10, repsUpper: 15, restSeconds: 75),
            .init(name: "坐姿双杠臂屈伸", muscleGroup: "手臂", equipment: "器械", sets: 3, repsLower: 8, repsUpper: 12, restSeconds: 90),
            .init(name: "绳索过顶臂屈伸", muscleGroup: "手臂", equipment: "龙门架", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 75),
            .init(name: "绳索下压", muscleGroup: "手臂", equipment: "龙门架", sets: 4, repsLower: 12, repsUpper: 15, restSeconds: 60)
        ], guidance: focusedTrainingGuidance),
        .init(code: "BACK_BI_R2", title: "背部＋二头 · 高集中容量", weekday: 4, exercises: [
            .init(name: "引体向上", muscleGroup: "背部", equipment: "自重", sets: 4, repsLower: 6, repsUpper: 8, restSeconds: 180, volumeUnitRaw: ExerciseVolumeUnit.count.rawValue, note: "不能稳定达到下限时使用辅助；不为凑次数摆动"),
            .init(name: "中立握高位下拉", muscleGroup: "背部", equipment: "器械", sets: 4, repsLower: 8, repsUpper: 12, restSeconds: 150),
            .init(name: "胸托划船", muscleGroup: "背部", equipment: "器械或哑铃", sets: 4, repsLower: 8, repsUpper: 10, restSeconds: 150),
            .init(name: "单臂绳索划船至髋", muscleGroup: "背部", equipment: "龙门架", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 90, unilateral: true),
            .init(name: "直臂下压", muscleGroup: "背部", equipment: "龙门架", sets: 3, repsLower: 12, repsUpper: 15, restSeconds: 75),
            .init(name: "上斜哑铃弯举", muscleGroup: "手臂", equipment: "哑铃", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 75),
            .init(name: "牧师凳弯举", muscleGroup: "手臂", equipment: "器械或曲杆", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 75),
            .init(name: "锤式弯举", muscleGroup: "手臂", equipment: "哑铃", sets: 2, repsLower: 12, repsUpper: 15, restSeconds: 60)
        ], guidance: focusedTrainingGuidance),
        .init(code: "LEGS_CORE_R2", title: "腿部＋核心 · 力量基础", weekday: 6, exercises: [
            .init(name: "箱跳", muscleGroup: "腿部", equipment: "跳箱", sets: 3, repsLower: 3, repsUpper: 3, restSeconds: 90, volumeUnitRaw: ExerciseVolumeUnit.count.rawValue, note: "每次稳定落地；动作质量下降或下肢不适时省略"),
            .init(name: "前蹲", muscleGroup: "腿部", equipment: "杠铃", sets: 4, repsLower: 6, repsUpper: 8, restSeconds: 180, note: "不使用 15 次高次数硬撑；保持躯干和髋部位置"),
            .init(name: "罗马尼亚硬拉", muscleGroup: "臀部", equipment: "杠铃", sets: 3, repsLower: 6, repsUpper: 8, restSeconds: 180, note: "髋后移、背部中立；腰背主导时立即减重或缩短幅度"),
            .init(name: "钟摆深蹲", muscleGroup: "腿部", equipment: "器械", sets: 4, repsLower: 8, repsUpper: 12, restSeconds: 150),
            .init(name: "保加利亚分腿蹲", muscleGroup: "腿部", equipment: "哑铃", sets: 3, repsLower: 8, repsUpper: 10, restSeconds: 120, unilateral: true),
            .init(name: "坐姿腿弯举", muscleGroup: "腿部", equipment: "器械", sets: 4, repsLower: 10, repsUpper: 15, restSeconds: 90),
            .init(name: "臀推", muscleGroup: "臀部", equipment: "杠铃或器械", sets: 3, repsLower: 8, repsUpper: 12, restSeconds: 120),
            .init(name: "站姿提踵", muscleGroup: "小腿", equipment: "器械", sets: 3, repsLower: 12, repsUpper: 15, restSeconds: 75),
            .init(name: "抗旋转推", muscleGroup: "核心", equipment: "龙门架", sets: 2, repsLower: 10, repsUpper: 12, restSeconds: 60, unilateral: true),
            .init(name: "绳索躯干旋转", muscleGroup: "核心", equipment: "龙门架", sets: 2, repsLower: 10, repsUpper: 12, restSeconds: 60, unilateral: true)
        ], guidance: focusedTrainingGuidance),
        .init(code: "SHOULDERS_ARMS_R2", title: "肩部＋手臂 · 高集中容量", weekday: 1, exercises: [
            .init(name: "地雷管推举", muscleGroup: "肩部", equipment: "杠铃", sets: 3, repsLower: 8, repsUpper: 10, restSeconds: 120, unilateral: true),
            .init(name: "器械肩推", muscleGroup: "肩部", equipment: "器械", sets: 3, repsLower: 8, repsUpper: 10, restSeconds: 120),
            .init(name: "绳索侧平举", muscleGroup: "肩部", equipment: "龙门架", sets: 5, repsLower: 12, repsUpper: 15, restSeconds: 60, unilateral: true),
            .init(name: "反向蝴蝶机", muscleGroup: "肩部", equipment: "器械", sets: 4, repsLower: 12, repsUpper: 15, restSeconds: 60),
            .init(name: "上斜哑铃弯举", muscleGroup: "手臂", equipment: "哑铃", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 75),
            .init(name: "牧师凳弯举", muscleGroup: "手臂", equipment: "器械或曲杆", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 75),
            .init(name: "绳索过顶臂屈伸", muscleGroup: "手臂", equipment: "龙门架", sets: 3, repsLower: 10, repsUpper: 12, restSeconds: 75),
            .init(name: "绳索下压", muscleGroup: "手臂", equipment: "龙门架", sets: 3, repsLower: 12, repsUpper: 15, restSeconds: 60)
        ], guidance: focusedTrainingGuidance)
    ]

    private static let weekdayFocusedCardioWorkouts: [ProgramCardioDraft] = [
        .init(code: "ROPE_THU_R2", title: "跳绳间歇", weekday: 5, timing: "下午或晚上", activeSeconds: 600, elapsedSeconds: 1200, intervals: "10 轮：跳 60 秒／休 60 秒", guidance: jumpRopeGuidance),
        .init(code: "ZONE2_THU_R2", title: "Zone 2 单车", weekday: 5, timing: "跳绳后分开完成或另选时段", activeSeconds: 1500, elapsedSeconds: 2100, intervals: "热身 5 分钟＋稳定 20–25 分钟＋放松 5 分钟", guidance: "使用单车或椭圆机，保持可以说短句的稳定强度；下肢恢复差时只做其中一项。"),
        .init(code: "ROPE_SAT_OPTIONAL_R2", title: "可选短跳绳", weekday: 7, timing: "仅本人主动选择", activeSeconds: 500, elapsedSeconds: 1200, intervals: "10 轮：跳 50 秒／休 70 秒", guidance: "周末默认留给家庭和恢复；不自动补课。本人主动选择且腿部、足踝恢复良好时才完成。")
    ]

    private static let confirmedCardioWorkouts: [ProgramCardioDraft] = [
        .init(code: "ROPE_TUE", title: "跳绳间歇", weekday: 3, timing: "下午或晚上", activeSeconds: 600, elapsedSeconds: 1200, intervals: "10 轮：跳 60 秒／休 60 秒", guidance: jumpRopeGuidance),
        .init(code: "ZONE2_FRI", title: "Zone 2 单车", weekday: 6, timing: "任意方便时段", activeSeconds: 1800, elapsedSeconds: 2400, intervals: "热身 5 分钟＋稳定 30 分钟＋放松 5 分钟", guidance: "使用单车或椭圆机，保持可以说短句的稳定强度；不以出汗量判断效果。"),
        .init(code: "ROPE_SUN", title: "跳绳间歇", weekday: 1, timing: "下午或晚上", activeSeconds: 500, elapsedSeconds: 1200, intervals: "10 轮：跳 50 秒／休 70 秒", guidance: jumpRopeGuidance)
    ]

    static func workout(on date: Date, preference: TrainingPreferenceSnapshot) -> ProgramWorkoutDraft? {
        let weekday = FatLossCalendar.calendar.component(.weekday, from: date)
        return workouts(preference: preference).first { $0.weekday == weekday }
    }

}
