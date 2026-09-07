import Foundation

/// Original cooking combinations. Reference amounts describe a two-portion batch, not a medical prescription.
enum FatLossCatalog {
    static let guidance = "七组双日午晚餐与四款早餐轮换。每张卡为两份烹饪示例，个人主食和蛋白食物量待医生/营养师确认；营养未核算。吃完再记录实际份数，不把计划当成已吃。"
    static let jumpRopeGuidance = "每周二、周六各一次；每次全程约30分钟，其中有效跳绳8–10分钟、约1500–1600次，分段完成。分开记录总时长、有效时长和次数，不把休息计为有效跳绳；不舒服或膝踝疼痛时停止，不为凑次数硬跳。"
    static let coordinationGuidance = "周六可选15–20分钟低疲劳协调练习：扶稳单脚平衡、交替脚步和轻松抛接球；跳绳后已有疲劳时省略，不额外追求疲劳。"
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

    static let trainingGuidance = "周一A、周三B、周五C，热身约10分钟，全程60–75分钟。每组保留约3次余力；首两周不力竭。工作重量由用户当天选择，不预设负重。连续两次以良好动作完成次数上限且恢复正常，才由用户手动最小幅度加重。可选第4天只做轻活动与协调，不强加力量训练。"

    static let workouts: [ProgramWorkoutDraft] = [
        .init(code: "A", title: "全身 A", weekday: 2, exercises: [
            .init(name: "腿举", muscleGroup: "腿部", equipment: "腿举机", repsLower: 8, repsUpper: 12, restSeconds: 150),
            .init(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃", repsLower: 6, repsUpper: 10, restSeconds: 150),
            .init(name: "坐姿划船", muscleGroup: "背部", equipment: "器械", repsLower: 8, repsUpper: 12, restSeconds: 120),
            .init(name: "腿弯举", muscleGroup: "腿部", equipment: "器械", repsLower: 10, repsUpper: 15, restSeconds: 90),
            .init(name: "侧平举", muscleGroup: "肩部", equipment: "哑铃", repsLower: 12, repsUpper: 15, restSeconds: 60),
            .init(name: "死虫", muscleGroup: "核心", equipment: "瑜伽垫", repsLower: 6, repsUpper: 10, restSeconds: 60, volumeUnitRaw: ExerciseVolumeUnit.count.rawValue, unilateral: true, note: "每侧6–10次；动作可控，腰背保持稳定")
        ], guidance: trainingGuidance),
        .init(code: "B", title: "全身 B", weekday: 4, exercises: [
            .init(name: "罗马尼亚硬拉", muscleGroup: "腿部", equipment: "杠铃", repsLower: 6, repsUpper: 10, restSeconds: 180),
            .init(name: "上斜哑铃卧推", muscleGroup: "胸部", equipment: "哑铃", repsLower: 8, repsUpper: 12, restSeconds: 150),
            .init(name: "高位下拉", muscleGroup: "背部", equipment: "器械", repsLower: 8, repsUpper: 12, restSeconds: 120),
            .init(name: "扶稳的反向箭步蹲", muscleGroup: "腿部", equipment: "自重／稳定支撑", repsLower: 8, repsUpper: 8, restSeconds: 90, volumeUnitRaw: ExerciseVolumeUnit.count.rawValue, unilateral: true, note: "每侧8次；扶稳支撑，优先稳定动作，保留约3次余力"),
            .init(name: "抗旋转推", muscleGroup: "核心", equipment: "绳索", repsLower: 10, repsUpper: 10, restSeconds: 60, unilateral: true, note: "每侧10次；负重当天选择，保持躯干稳定")
        ], guidance: trainingGuidance),
        .init(code: "C", title: "全身 C", weekday: 6, exercises: [
            .init(name: "高脚杯深蹲", muscleGroup: "腿部", equipment: "哑铃", repsLower: 8, repsUpper: 12, restSeconds: 150),
            .init(name: "器械推胸", muscleGroup: "胸部", equipment: "器械", repsLower: 8, repsUpper: 12, restSeconds: 120),
            .init(name: "胸托划船", muscleGroup: "背部", equipment: "器械", repsLower: 8, repsUpper: 12, restSeconds: 120),
            .init(name: "臀推", muscleGroup: "臀部", equipment: "杠铃或器械", repsLower: 8, repsUpper: 12, restSeconds: 120),
            .init(name: "轻重量农夫走", muscleGroup: "核心", equipment: "哑铃", repsLower: 30, repsUpper: 30, restSeconds: 90, volumeUnitRaw: ExerciseVolumeUnit.meter.rawValue, note: "每组走1趟30米，共2组；轻重量由用户选择，距离单独记录，不当成30次重复")
        ], guidance: trainingGuidance)
    ]

    static func workout(on date: Date) -> ProgramWorkoutDraft? {
        let weekday = FatLossCalendar.calendar.component(.weekday, from: date)
        return workouts.first { $0.weekday == weekday }
    }

}
