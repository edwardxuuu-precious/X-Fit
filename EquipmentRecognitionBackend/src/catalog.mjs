export const catalogVersion = "2026.08.22";

export const equipmentCatalog = [
  {
    id: "pendulum_squat_machine",
    nameZH: "钟摆深蹲机",
    nameEN: "Pendulum Squat Machine",
    aliases: ["pendulum", "pendulum squat", "hammer strength"],
    primaryMuscles: ["腿部", "臀部"],
    secondaryMuscles: ["小腿", "核心"],
    exercises: [
      ["machine_pendulum_squat", "钟摆深蹲机", "Pendulum Squat"]
    ]
  },
  {
    id: "smith_machine",
    nameZH: "史密斯机",
    nameEN: "Smith Machine",
    aliases: ["史密斯", "smith", "smith rack"],
    primaryMuscles: ["胸部", "肩部", "腿部"],
    secondaryMuscles: ["手臂", "臀部", "核心"],
    exercises: [
      ["smith_machine_bench_press", "史密斯机平板卧推", "Smith Machine Bench Press"],
      ["smith_machine_incline_bench_press", "史密斯机上斜卧推", "Smith Machine Incline Bench Press"],
      ["smith_machine_shoulder_press", "史密斯机肩上推举", "Smith Machine Shoulder Press"]
    ]
  },
  {
    id: "lat_pulldown_machine",
    nameZH: "高位下拉机",
    nameEN: "Lat Pulldown Machine",
    aliases: ["高位下拉", "lat pulldown"],
    primaryMuscles: ["背部"],
    secondaryMuscles: ["手臂", "肩部"],
    exercises: [["lat_pulldown", "高位下拉", "Lat Pulldown"]]
  },
  {
    id: "leg_press_machine",
    nameZH: "腿举机",
    nameEN: "Leg Press Machine",
    aliases: ["腿举", "腿推", "leg press"],
    primaryMuscles: ["腿部", "臀部"],
    secondaryMuscles: ["小腿"],
    exercises: [["machine_leg_press", "器械腿举", "Leg Press"]]
  },
  {
    id: "cable_machine",
    nameZH: "龙门架",
    nameEN: "Cable Machine",
    aliases: ["绳索", "拉力器", "cable", "functional trainer"],
    primaryMuscles: ["胸部", "背部", "肩部", "手臂"],
    secondaryMuscles: ["核心"],
    exercises: [
      ["standing_cable_chest_fly", "站姿绳索夹胸", "Standing Cable Chest Fly"],
      ["cable_face_pull", "绳索面拉", "Cable Face Pull"],
      ["cable_triceps_pushdown", "绳索下压", "Cable Triceps Pushdown"]
    ]
  }
];

export function localCatalogMatch(text) {
  const target = String(text ?? "").toLocaleLowerCase();
  return equipmentCatalog.find((item) =>
    [item.id, item.nameZH, item.nameEN, ...item.aliases]
      .some((value) => target.includes(value.toLocaleLowerCase()))
  );
}

export function responseForCatalogItem(item, evidence = [], confidence = 0.72) {
  return {
    analysisID: crypto.randomUUID(),
    machine: {
      canonicalID: item.id,
      nameZH: item.nameZH,
      nameEN: item.nameEN,
      confidence,
      evidence: evidence.slice(0, 4)
    },
    exerciseCandidates: item.exercises.map(([canonicalID, nameZH, nameEN]) => ({
      canonicalID,
      nameZH,
      nameEN,
      primaryMuscles: item.primaryMuscles,
      secondaryMuscles: item.secondaryMuscles,
      confidence
    })),
    needsConfirmation: true,
    warnings: confidence < 0.8
      ? ["照片或标牌信息有限，请在加入训练前确认器械和动作。"]
      : []
  };
}
