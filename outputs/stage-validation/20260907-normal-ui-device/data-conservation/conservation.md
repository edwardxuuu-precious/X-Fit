# 下载备份数据守恒审计

仅打开含 WAL/SHM 的临时工作副本；原始备份哈希前后校验。全部含 ZID 的实体均纳入，内部 Z_PK/Z_ENT/Z_OPT 单列；新增表/列不冒充旧字段比较。

- pre-install：14 个实体，1257 行；完整性 ['ok']；原始文件未变 True。
- post-install：22 个实体，1257 行；完整性 ['ok']；原始文件未变 True。
- retry-pre-install：22 个实体，1257 行；完整性 ['ok']；原始文件未变 True。
- retry-post-install：22 个实体，1257 行；完整性 ['ok']；原始文件未变 True。
- retry-post-tests：22 个实体，1257 行；完整性 ['ok']；原始文件未变 True。
- post-supplement：22 个实体，1257 行；完整性 ['ok']；原始文件未变 True。
- final-release：22 个实体，1257 行；完整性 ['ok']；原始文件未变 True。

## pre-install → post-install

状态：`PASS_COMMON_HISTORY_PRESERVED`；原 UUID 缺失 0，新增 0，共同记录业务变化 0。

| 表 | 原行数 | 后行数 | UUID 缺失 | UUID 新增 | 业务变化 | 新增列 |
|---|---:|---:|---:|---:|---:|---:|
| ZBODYMEASUREMENT | 0 | 0 | 0 | 0 | 0 | 0 |
| ZDAILYBODYCHECKIN | 5 | 5 | 0 | 0 | 0 | 0 |
| ZEXERCISE | 92 | 92 | 0 | 0 | 0 | 0 |
| ZHYDRATIONENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZJUMPROPEENTRY | 0 | 0 | 0 | 0 | 0 | 2 |
| ZMEALENTRY | 0 | 0 | 0 | 0 | 0 | 12 |
| ZNUTRITIONTARGET | 1 | 1 | 0 | 0 | 0 | 0 |
| ZSCHEDULEDWORKOUT | 23 | 23 | 0 | 0 | 0 | 0 |
| ZSEDENTARYSESSION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZSESSIONEXERCISE | 203 | 203 | 0 | 0 | 0 | 0 |
| ZSETLOG | 837 | 837 | 0 | 0 | 0 | 0 |
| ZTEMPLATEEXERCISE | 50 | 50 | 0 | 0 | 0 | 0 |
| ZWORKOUTSESSION | 36 | 36 | 0 | 0 | 0 | 0 |
| ZWORKOUTTEMPLATE | 10 | 10 | 0 | 0 | 0 | 0 |

新增实体：ZFATLOSSPROGRAM, ZPLANNEDMEAL, ZPROGRAMDAILYLOG, ZPROGRAMHEALTHRECORD, ZPROGRAMTARGETREVISION, ZPROGRAMWEEKLYREVIEW, ZPROGRAMWORKOUTLINK, ZRECIPEVERSION。
缺失实体：无。

## post-install → retry-pre-install

状态：`REQUIRES_CHANGE_REVIEW`；原 UUID 缺失 0，新增 0，共同记录业务变化 1。

| 表 | 原行数 | 后行数 | UUID 缺失 | UUID 新增 | 业务变化 | 新增列 |
|---|---:|---:|---:|---:|---:|---:|
| ZBODYMEASUREMENT | 0 | 0 | 0 | 0 | 0 | 0 |
| ZDAILYBODYCHECKIN | 5 | 5 | 0 | 0 | 0 | 0 |
| ZEXERCISE | 92 | 92 | 0 | 0 | 1 | 0 |
| ZFATLOSSPROGRAM | 0 | 0 | 0 | 0 | 0 | 0 |
| ZHYDRATIONENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZJUMPROPEENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZMEALENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZNUTRITIONTARGET | 1 | 1 | 0 | 0 | 0 | 0 |
| ZPLANNEDMEAL | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMDAILYLOG | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMHEALTHRECORD | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMTARGETREVISION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMWEEKLYREVIEW | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMWORKOUTLINK | 0 | 0 | 0 | 0 | 0 | 0 |
| ZRECIPEVERSION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZSCHEDULEDWORKOUT | 23 | 23 | 0 | 0 | 0 | 0 |
| ZSEDENTARYSESSION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZSESSIONEXERCISE | 203 | 203 | 0 | 0 | 0 | 0 |
| ZSETLOG | 837 | 837 | 0 | 0 | 0 | 0 |
| ZTEMPLATEEXERCISE | 50 | 50 | 0 | 0 | 0 | 0 |
| ZWORKOUTSESSION | 36 | 36 | 0 | 0 | 0 | 0 |
| ZWORKOUTTEMPLATE | 10 | 10 | 0 | 0 | 0 | 0 |

新增实体：无。
缺失实体：无。

## retry-pre-install → retry-post-install

状态：`REQUIRES_CHANGE_REVIEW`；原 UUID 缺失 0，新增 0，共同记录业务变化 1。

| 表 | 原行数 | 后行数 | UUID 缺失 | UUID 新增 | 业务变化 | 新增列 |
|---|---:|---:|---:|---:|---:|---:|
| ZBODYMEASUREMENT | 0 | 0 | 0 | 0 | 0 | 0 |
| ZDAILYBODYCHECKIN | 5 | 5 | 0 | 0 | 0 | 0 |
| ZEXERCISE | 92 | 92 | 0 | 0 | 1 | 0 |
| ZFATLOSSPROGRAM | 0 | 0 | 0 | 0 | 0 | 0 |
| ZHYDRATIONENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZJUMPROPEENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZMEALENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZNUTRITIONTARGET | 1 | 1 | 0 | 0 | 0 | 0 |
| ZPLANNEDMEAL | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMDAILYLOG | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMHEALTHRECORD | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMTARGETREVISION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMWEEKLYREVIEW | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMWORKOUTLINK | 0 | 0 | 0 | 0 | 0 | 0 |
| ZRECIPEVERSION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZSCHEDULEDWORKOUT | 23 | 23 | 0 | 0 | 0 | 0 |
| ZSEDENTARYSESSION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZSESSIONEXERCISE | 203 | 203 | 0 | 0 | 0 | 0 |
| ZSETLOG | 837 | 837 | 0 | 0 | 0 | 0 |
| ZTEMPLATEEXERCISE | 50 | 50 | 0 | 0 | 0 | 0 |
| ZWORKOUTSESSION | 36 | 36 | 0 | 0 | 0 | 0 |
| ZWORKOUTTEMPLATE | 10 | 10 | 0 | 0 | 0 | 0 |

新增实体：无。
缺失实体：无。

## retry-post-install → retry-post-tests

状态：`REQUIRES_CHANGE_REVIEW`；原 UUID 缺失 0，新增 0，共同记录业务变化 1。

| 表 | 原行数 | 后行数 | UUID 缺失 | UUID 新增 | 业务变化 | 新增列 |
|---|---:|---:|---:|---:|---:|---:|
| ZBODYMEASUREMENT | 0 | 0 | 0 | 0 | 0 | 0 |
| ZDAILYBODYCHECKIN | 5 | 5 | 0 | 0 | 0 | 0 |
| ZEXERCISE | 92 | 92 | 0 | 0 | 1 | 0 |
| ZFATLOSSPROGRAM | 0 | 0 | 0 | 0 | 0 | 0 |
| ZHYDRATIONENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZJUMPROPEENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZMEALENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZNUTRITIONTARGET | 1 | 1 | 0 | 0 | 0 | 0 |
| ZPLANNEDMEAL | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMDAILYLOG | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMHEALTHRECORD | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMTARGETREVISION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMWEEKLYREVIEW | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMWORKOUTLINK | 0 | 0 | 0 | 0 | 0 | 0 |
| ZRECIPEVERSION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZSCHEDULEDWORKOUT | 23 | 23 | 0 | 0 | 0 | 0 |
| ZSEDENTARYSESSION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZSESSIONEXERCISE | 203 | 203 | 0 | 0 | 0 | 0 |
| ZSETLOG | 837 | 837 | 0 | 0 | 0 | 0 |
| ZTEMPLATEEXERCISE | 50 | 50 | 0 | 0 | 0 | 0 |
| ZWORKOUTSESSION | 36 | 36 | 0 | 0 | 0 | 0 |
| ZWORKOUTTEMPLATE | 10 | 10 | 0 | 0 | 0 | 0 |

新增实体：无。
缺失实体：无。

## retry-post-tests → post-supplement

状态：`PASS_COMMON_HISTORY_PRESERVED`；原 UUID 缺失 0，新增 0，共同记录业务变化 0。

| 表 | 原行数 | 后行数 | UUID 缺失 | UUID 新增 | 业务变化 | 新增列 |
|---|---:|---:|---:|---:|---:|---:|
| ZBODYMEASUREMENT | 0 | 0 | 0 | 0 | 0 | 0 |
| ZDAILYBODYCHECKIN | 5 | 5 | 0 | 0 | 0 | 0 |
| ZEXERCISE | 92 | 92 | 0 | 0 | 0 | 0 |
| ZFATLOSSPROGRAM | 0 | 0 | 0 | 0 | 0 | 0 |
| ZHYDRATIONENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZJUMPROPEENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZMEALENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZNUTRITIONTARGET | 1 | 1 | 0 | 0 | 0 | 0 |
| ZPLANNEDMEAL | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMDAILYLOG | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMHEALTHRECORD | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMTARGETREVISION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMWEEKLYREVIEW | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMWORKOUTLINK | 0 | 0 | 0 | 0 | 0 | 0 |
| ZRECIPEVERSION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZSCHEDULEDWORKOUT | 23 | 23 | 0 | 0 | 0 | 0 |
| ZSEDENTARYSESSION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZSESSIONEXERCISE | 203 | 203 | 0 | 0 | 0 | 0 |
| ZSETLOG | 837 | 837 | 0 | 0 | 0 | 0 |
| ZTEMPLATEEXERCISE | 50 | 50 | 0 | 0 | 0 | 0 |
| ZWORKOUTSESSION | 36 | 36 | 0 | 0 | 0 | 0 |
| ZWORKOUTTEMPLATE | 10 | 10 | 0 | 0 | 0 | 0 |

新增实体：无。
缺失实体：无。

## post-supplement → final-release

状态：`REQUIRES_CHANGE_REVIEW`；原 UUID 缺失 0，新增 0，共同记录业务变化 1。

| 表 | 原行数 | 后行数 | UUID 缺失 | UUID 新增 | 业务变化 | 新增列 |
|---|---:|---:|---:|---:|---:|---:|
| ZBODYMEASUREMENT | 0 | 0 | 0 | 0 | 0 | 0 |
| ZDAILYBODYCHECKIN | 5 | 5 | 0 | 0 | 0 | 0 |
| ZEXERCISE | 92 | 92 | 0 | 0 | 1 | 0 |
| ZFATLOSSPROGRAM | 0 | 0 | 0 | 0 | 0 | 0 |
| ZHYDRATIONENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZJUMPROPEENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZMEALENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZNUTRITIONTARGET | 1 | 1 | 0 | 0 | 0 | 0 |
| ZPLANNEDMEAL | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMDAILYLOG | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMHEALTHRECORD | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMTARGETREVISION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMWEEKLYREVIEW | 0 | 0 | 0 | 0 | 0 | 0 |
| ZPROGRAMWORKOUTLINK | 0 | 0 | 0 | 0 | 0 | 0 |
| ZRECIPEVERSION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZSCHEDULEDWORKOUT | 23 | 23 | 0 | 0 | 0 | 0 |
| ZSEDENTARYSESSION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZSESSIONEXERCISE | 203 | 203 | 0 | 0 | 0 | 0 |
| ZSETLOG | 837 | 837 | 0 | 0 | 0 | 0 |
| ZTEMPLATEEXERCISE | 50 | 50 | 0 | 0 | 0 | 0 |
| ZWORKOUTSESSION | 36 | 36 | 0 | 0 | 0 | 0 |
| ZWORKOUTTEMPLATE | 10 | 10 | 0 | 0 | 0 | 0 |

新增实体：无。
缺失实体：无。

## pre-install → final-release

状态：`REQUIRES_CHANGE_REVIEW`；原 UUID 缺失 0，新增 0，共同记录业务变化 1。

| 表 | 原行数 | 后行数 | UUID 缺失 | UUID 新增 | 业务变化 | 新增列 |
|---|---:|---:|---:|---:|---:|---:|
| ZBODYMEASUREMENT | 0 | 0 | 0 | 0 | 0 | 0 |
| ZDAILYBODYCHECKIN | 5 | 5 | 0 | 0 | 0 | 0 |
| ZEXERCISE | 92 | 92 | 0 | 0 | 1 | 0 |
| ZHYDRATIONENTRY | 0 | 0 | 0 | 0 | 0 | 0 |
| ZJUMPROPEENTRY | 0 | 0 | 0 | 0 | 0 | 2 |
| ZMEALENTRY | 0 | 0 | 0 | 0 | 0 | 12 |
| ZNUTRITIONTARGET | 1 | 1 | 0 | 0 | 0 | 0 |
| ZSCHEDULEDWORKOUT | 23 | 23 | 0 | 0 | 0 | 0 |
| ZSEDENTARYSESSION | 0 | 0 | 0 | 0 | 0 | 0 |
| ZSESSIONEXERCISE | 203 | 203 | 0 | 0 | 0 | 0 |
| ZSETLOG | 837 | 837 | 0 | 0 | 0 | 0 |
| ZTEMPLATEEXERCISE | 50 | 50 | 0 | 0 | 0 | 0 |
| ZWORKOUTSESSION | 36 | 36 | 0 | 0 | 0 | 0 |
| ZWORKOUTTEMPLATE | 10 | 10 | 0 | 0 | 0 | 0 |

新增实体：ZFATLOSSPROGRAM, ZPLANNEDMEAL, ZPROGRAMDAILYLOG, ZPROGRAMHEALTHRECORD, ZPROGRAMTARGETREVISION, ZPROGRAMWEEKLYREVIEW, ZPROGRAMWORKOUTLINK, ZRECIPEVERSION。
缺失实体：无。

字段变化需要对照当前迁移代码与授权逐项解释，不自动认定为正常迁移或损坏。此结果只证明这些下载时间点；不替代最后 Release 回读或人工验收。
