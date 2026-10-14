# تحليل سكربت `w_medic`

**المسار:** `resources\[wraith]\w_medic\`
**التاريخ:** 2026-10-13
**النوع:** نظام الأطباء الكامل لـ RedM — وظائف، إصابات، نزيف، آخر محاولة، موت، أسرة، صيدلية.

---

## البنية

| الملف | الأسطر | الدور |
|---|---|---|
| `config.lua` | ~700 | كل الإعدادات: المواقع، الإصابات، النزيف، تصنيف الأسلحة |
| `server/main.lua` | 820 | التحقق على السيرفر، الصيدلية، الأسرّة، الأوامر، callbacks |
| `client/main.lua` | 1074 | محرّك الإصابات، كاميرا السرير، wound logic |
| `client/job.lua` | 447 | الـ prompts (سلاح/مناوبة/عربات/خزنة/أسرة)، منطق الطبيب مع المريض |
| `client/wounding.lua` | 247 | الضمادات، المسكنات، محرّك النزيف |
| `client/laststand.lua` | 114 | آخر محاولة + الإحياء بالـ kit |
| `client/dead.lua` | 183 | شاشة الموت، العدّاد، `OnDeath`، سجلّ الموت |
| `tests/test_pharmacy.py` | 227 | اختبار الصيدلية عبر `lupa` — يشغّل أسطر `server/main.lua` نفسها |
| `tests/test_pay.py` | 165 | اختبار `payDoctor` + مفتاح الراتب من `w_core` |

### التبعيات

| المورد | الدور |
|---|---|
| `w_lib` | القاموس، الإشعارات، NUI prompts، blips، الجسر مع الحقيبة |
| `w_core` | callbacks، commands، metadata اللاعب |
| `oxmysql` | قاعدة البيانات |
| `w_centralbank` | تحويل الأموال (فاتورة المريض، أجر الطبيب) |
| `w_hud` | الجوع والعطش (`SetNeed`) |
| `w_creators` | القيامة، العمليات التجميلية، منع تبديل الشخصية |
| `w_inventory` / `vorp_inventory` / `rsg-inventory` / `qbr-inventory` | الحقيبة — يختارها `w_lib:InvName()` |
| `evidence` | بقع الدم |
| `monitor` (txAdmin) | تكامل مع خيارات الشفاء |

---

## نقاط القوة

### 1. الأمان مغطّى على السيرفر بشكل ممتاز

كل الأحداث الحساسة تتحقق قبل التنفيذ — وهذا نادر في موارد FiveM/RedM:

| الحدث | الفحوص |
|---|---|
| `hospital:server:TreatWounds` (`server/main.lua:410`) | الوظيفة + المناوبة + مسافة + routing bucket + استهلاك الضمادة |
| `hospital:server:RevivePlayer` (`server/main.lua:453`) | نفس الفحوص + الحقيبة |
| `hospital:server:SendToBed` (`server/main.lua:279`) | `atHospital` — موقع السيرفر يمنع teleport من بعيد |
| `hospital:server:requestCosmeticSurgery` (`server/main.lua:515`) | cooldown + سجلّ العيادة + حالة اللاعب |

والكود يشرح **ليش** بالضبط، مثلاً `server/main.lua:388`:

> a modified client can send any id: heal a friend across the map or in another
> routing bucket, off duty, without a bandage, with a full belly and full
> water on top (refillNeeds). So the server checks what it knows itself.

**`withinReach`** (`server/main.lua:403`) تتحقق من مسافة حقيقية محسوبة على السيرفر + نفس routing bucket:

```lua
local function withinReach(a, b, reach)
    if GetPlayerRoutingBucket(a) ~= GetPlayerRoutingBucket(b) then return false end
    local pedA, pedB = GetPlayerPed(a), GetPlayerPed(b)
    if not pedA or pedA == 0 or not pedB or pedB == 0 then return false end
    return #(GetEntityCoords(pedA) - GetEntityCoords(pedB)) <= reach
end
```

### 2. نظام الدفع `payDoctor` مصمّم بذكاء

`server/main.lua:29` — مفتاح التكرار يحمل **مَن، لمن، ومتى**:

```lua
local ok = exports.w_centralbank:Transfer('society:ambulance', 'player:' .. cid .. ':bank', amount,
    ('doctor-%s:%s:%s:%s'):format(kind, cid, src, GetGameTimer()))
```

- يمنع دفع نفس العلاج مرتين لنفس الج_ICW.
- يسمح لدكين على نفس المريض بنفس اللحظة — لأنهما عملان حقيقيان.
- الدفع من `society:ambulance` (نفس حساب فاتورة المريض) → **الوظيفة تموّل نفسها**.
- يُستدعى **بعد** استهلاك الضمادة/الحقيبة (`سطر 433` و `471`) — لا أحد يطلب بدون شغل.

### 3. الجوع والعطش على السيرفر — `refillNeeds`

`server/main.lua:224`. الكلاينت ما يقدر يعبّي حاجاته بنفسه لأن `w_core` يرفض `WCore:Server:SetMetaData` عمداً. الـ fallback موجود إذا `w_hud` مش شغّال، وكل استدعاء داخل `pcall` حتى لا يكسر الشفاء لو `w_hud` يعيد التشغيل.

### 4. توافق مع أربع حقائب مختلفة

`setupPharmacy` (`server/main.lua:77`) يختار الشكل حسب الحقيبة الفعلية:

- **`w_inventory`** → `RegisterShop` حقيقي. الحقيبة تطبق المخزون والمجموعة بنفسها.
- **`vorp` / `rsg` / `qbr`** → handout يديره السيرفر: الوظيفة، المناوبة، المخزون، نافذة زمنية، مساحة الحقيبة.

تعليق صريح في الكود:
> The handout is not a downgrade: the server decides who gets what and how often,
> which is the same authority the shop had.

### 5. `bedGeneration` — أنضج معالجة لـ character switch

`client/main.lua:12`. كل thread فيه السرير (كاميرا، علاج AI، أنيميشن الخروج) يقرأ نفس العدّاد، وأي قيمة أحدث تُلغي القديم فوراً. يمنع:
- علاج `%s` قديم بعد logout أو تبديل شخصية
- كاميرا من سرير سابق بعد تحميل شخصية جديدة
- سرير محجوز لحد ما `_player` يخرج منه فعلاً

### 6. تبديل اللغة حيّ

`client/job.lua:255` — `w_lib:setLocale` يعيد بناء كل النصوص:

```lua
AddEventHandler('w_lib:setLocale', function(key)
    w.locale(key)
    RebuildStationBlips()
    for i = 1, #stationPrompts do stationPrompts[i].relabel() end
    relabelPatientPrompt()
    RelabelBedPrompt()
    RelabelDeathPrompt()
end)
```

### 7. الاختبارات تشغّل الكود الحقيقي

`tests/*.py` تستخدم `lupa.lua54` وتقصّ **الأسطر نفسها** من `server/main.lua` بمؤشرات markers، بدل ما تكتب نسخة منفصلة. هذا يضمن أن الاختبار يفشل لو الكود تغيّر.

---

## المشاكل

### 🔴 حرجة

#### 1. مسار الاختبارات خاطئ — الاختبارات ميتة

`tests/test_pharmacy.py:12`:
```python
SRC = r"F:\Server RedM\Wraith Core\txData\WraithCore\resources\[wraith]\w_ambulancejob\server\main.lua"
```

`tests/test_pay.py:12-13`:
```python
AMB   = r"F:\Server RedM\Wraith Core\txData\WraithCore\resources\[wraith]\w_ambulancejob\server\main.lua"
LOOPS = r"F:\Server RedM\Wraith Core\txData\WraithCore\resources\[wraith]\w_core\server\loops.lua"
```

هذي مسارات سيرفر **آخر** (`Wraith Core`)، مو الحالي (`MajestyRP`). كما أن `w_core` أصلاً ليس في مسار هذا الـ workspace.

**الإصلاح:** تحويلها لمسار نسبي:

```python
import os
HERE    = os.path.dirname(os.path.abspath(__file__))
AMB_DIR = os.path.dirname(HERE)          # ...\w_ambulancejob
SRC     = os.path.join(AMB_DIR, 'server', 'main.lua')
LOOPS   = os.path.join(AMB_DIR, os.pardir, 'w_core', 'server', 'loops.lua')
```

#### 2. `takeSupplies` ما يتحقق من المسافة

الكلاينت يفحص `doctorUpright` قبل الإرسال (`client/job.lua:63`)، لكن السيرفر في `takeSupplies` (`server/main.lua:114`) يفحص: الوظيفة + المناوبة + المخزون + النافذة الزمنية + مساحة الحقيبة — **ما يفحص المسافة من الصيدلية**.

نتيجة: ملف معدّل يقدر `TriggerServerEvent('w_ambulancejob:takeSupplies')` من أي مكان بالخريطة. الأثر محدود (3 مرات / ساعة / طبيب) لكن الثغرة موجودة، والسكربت نفسه يدّعيMTV التحقق في كل مكان آخر.

**الإصلاح:** استخدام `atHospital`-style check — يتحقق اللاعب قرب أي موقع armory:

```lua
local function atAnyArmory(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pos = GetEntityCoords(ped)
    for _, desk in pairs(Config.Locations["armory"] or {}) do
        if #(pos - vector3(desk.x, desk.y, desk.z)) <= 10.0 then return true end
    end
    return false
end
```

#### 3. `PlayerInjuries` و `PlayerWeaponWounds` ما تنمسح عند خروج اللاعب

`server/main.lua:352-369`:
```lua
RegisterNetEvent('hospital:server:SyncInjuries', function(data)
    PlayerInjuries[src] = data
end)

RegisterNetEvent('hospital:server:SetWeaponDamage', function(data)
    PlayerWeaponWounds[Player.PlayerData.source] = data
end)
```

في `playerDropped` handler (`سطر 539`) ينمسح `surgeryRequests` و `releaseBed`، وفي handler منفصل (`سطر 155`) ينمسح `shelfTaken` — بس **ما في تنظيف لـ `PlayerInjuries` ولا `PlayerWeaponWounds`**. الـ server id يُعاد استخدامه بعد ال��روج، والبيانات القديمة تُسرَّب في الذاكرة حتى ريستارت المورد.

#### 4. `SendToBed` ما يتحقق إن اللاعب أصلاً في سرير — فاتورة قابلة للتكرار

`server/main.lua:279-288`:
```lua
RegisterNetEvent('hospital:server:SendToBed', function(bedId, isRevive)
    if not validBed(bedId) or not atHospital(src, bedId) then return end
    ...
    payHospital(Player)
end)
```

`atHospital` يتحقق من الموقع ✅، بس ما يتحقق `bedBySrc[src] == nil`. لاعب في سرير يرسل `SendToBed` مرة ثانية → `payHospital` ينفّذ فاتورة 25$ ثانية بدون rate-limit.

---

### 🟡 متوسطة

#### 5. `hospital:server:SetDoctor` يعدّ كل اللاعبين في كل مرة

`server/main.lua:436-445`:
```lua
RegisterNetEvent('hospital:server:SetDoctor', function()
    local amount = 0
    local players = WCore.Functions.GetWPlayers()
    for k,v in pairs(players) do
        if v.PlayerData.job.name == 'ambulance' and v.PlayerData.job.onduty then
            amount = amount + 1
        end
    end
    TriggerClientEvent("hospital:client:SetDoctorCount", -1, amount)
end)
```

يتنفّذ عند كل `/status`، كل تبديل مناوبة، وكل player load — ويبثّ النتيجة **لكل** اللاعبين. نفس النمط مكرر في:
- `hospital:server:ambulanceAlert` (`سطر 321`)
- `hospital:server:SendDoctorAlert` (`سطر 475`)
- `hospital:GetDoctors` callback (`سطر 546`)

مع 100 لاعب = 100 عدّ + 100 event لكل مرة. يستاهل cache بـ TTL (ثانية أو ثانيتين):

```lua
local doctorCountCache, doctorCountAt = 0, 0
local function onDutyDoctors()
    local now = GetGameTimer()
    if now - doctorCountAt < 2000 then return doctorCountCache end
    doctorCountAt = now
    local n = 0
    for _, v in pairs(WCore.Functions.GetWPlayers()) do
        if v.PlayerData.job.name == 'ambulance' and v.PlayerData.job.onduty then n = n + 1 end
    end
    doctorCountCache = n
    return n
end
```

#### 6. `CanHelp` فيه hardcode عند 300

`client/laststand.lua:78`:
```lua
RegisterNetEvent('hospital:client:CanHelp', function(helperId)
    if InLaststand then
        if LaststandTime <= 300 then
```

لكن `Config.MinimumRevive = 180` (`config.lua:34`) و `Laststand.MinimumRevive = Config.MinimumRevive` (`laststand.lua:3`). الـ `300` مكتوبة يدوياً — لو غيّرت الـ config، السطر هذا **ما يتبع**.

المفروض `Laststand.MinimumRevive`. وللمقارنة، `client/dead.lua:96` يستخدم `Laststand.MinimumRevive` بشكل صحيح:
```lua
local canAsk = LaststandTime <= Laststand.MinimumRevive
```

#### 7. `DispatchTimer * 4` — سليم حسابياً، لكن مضاعف غامض (تصحيح)

`config.lua:5`:
```lua
Config.DispatchTimer = 180 --DispatchTimer*4
```

`client/main.lua:712-721`:
```lua
local transG = 250
local blip = w.blip.create(...)
while transG ~= 0 do
    Wait(Config.DispatchTimer * 4)
    transG = transG - 1
    ...
end
```

**الحساب الصحيح:** `Wait(180 * 4)` = `Wait(720)` مللي ثانية لكل دورة × `250` دورة
= `180,000` مللي ثانية = **180 ثانية = 3 دقائق** بالضبط.

هذا **صحيح ومعقول** — الـ blip يبقى 3 دقائق. ~~الادعاء السابق بأن الـ blip يبقى 50 ساعة خطأ حسابي~~.

الباقي فقط: الرقم `180` مو مفهوم مباشرة (لو هو ثواني فالضرب غريب)، ويصير `180 * 4 * 250 = 180000` بالضبط مصادفة مقصودة أو حد مُعايَر بـ tick. يستحق **تعليق يشرح intent**، وتحويلها لصيغة أوضح مثل:

```lua
-- the alert blip lives for DispatchBlipSeconds (default 180 = 3 minutes)
local lifeMs = (tonumber(Config.DispatchBlipSeconds) or 180) * 1000
local steps, stepMs = 250, math.floor(lifeMs / 250)
```

#### 8. `ApplyBleed` معرّف في ملفين

- `client/main.lua:226-235`
- `client/wounding.lua:29-38`

نسختان متطابقتين من نفس المنطق:
```lua
local function ApplyBleed(level)
    if isBleeding ~= 4 then
        if isBleeding + level > 4 then
            isBleeding = 4
        else
            isBleeding = isBleeding + level
        end
        DoBleedAlert()
    end
end
```

نفس الشي `DoBleedAlert` معرّف في الاثنين أيضاً (`main.lua:220` و `wounding.lua:12`). لو أُصلح نسخة، الثانية تبقى المعتمدة فعلياً (لأن `wounding.lua` يُحمّل **بعد** `main.lua` في `fxmanifest.lua`، فالنسخة الأخيرة هي الفايدة).

**الإصلاح:** حذف التكرار من `wounding.lua` والاعتماد على تعريف `main.lua`.

#### 9. `SyncInjuries` يرسل نفس الـ payload مرتين

`client/main.lua:299-335` — في `ResetPartial`:
```lua
TriggerServerEvent('hospital:server:SyncInjuries', {
    limbs = BodyParts,
    isBleeding = tonumber(isBleeding)
})

ProcessRunStuff(PlayerPedId(), nil)
DoLimbAlert()
DoBleedAlert()

TriggerServerEvent('hospital:server:SyncInjuries', {      -- ← نفس الـ payload
    limbs = BodyParts,
    isBleeding = tonumber(isBleeding)
})
```

النفس المشكلة في `ResetAll` (`سطر 350` و `362`) — ثلاث مرات بدل مرة.

---

### 🔵 بسيطة

#### 10. `SetPain` يعطي `severity = 4` و `Config.WoundStates` عنده 4 عناصر

`client/main.lua:797`:
```lua
BodyParts[Config.Bones[14410]].severity = math.random(1, 4)
```

`config.lua:349-354` — `Config.WoundStates` فهرساته 1 إلى 4، الحامي `or ''` في الاستعمال موجود ✅ في كل مواضع الاستعمال. لكن الأفضل clamp عند المصدر بدل الاعتماد على الحامي:

```lua
severity = math.random(1, #Config.WoundStates)
```

وكذلك `CheckDamage` (`main.lua:554`) يستخدم `math.random(1, 3)` — ثابتة بينما问题的分包 في 4.

#### 11. `CheckDamage` ما يتحقق من الـ ped

`client/main.lua:546`:
```lua
local function CheckDamage(ped, bone, weapon, damageDone)
    if weapon == nil then return end
    if Config.Bones[bone] and not isDead and not InLaststand then
```

يُنادى حالياً بـ `PlayerPedId()` فقط (`سطر 1016`) ✅. لكن الدالة عامة بلا تحقق — لو استُدعيت على ped غيره مستقبلاً = rankings خاطئة. يفضل `if ped ~= PlayerPedId() then return end`.

#### 12. `onPainKillers` يتأخر كثيراً

`client/wounding.lua:136-150`:
```lua
painkillerAmount = painkillerAmount - 1
Wait(Config.PainkillerInterval * 1000)  -- 60 ثانية لكل جرعة
```

3 جرعات = 180 ثانية. المتعمّد على الأرجح (مفعول تراكمي) لكن بدون توثيق — صعب يميّز المتعمّد عن البق.

#### 13. `RespawnAtHospital` يستخدم `Player` بدون فحص nil

`server/main.lua:290-296`:
```lua
RegisterNetEvent('hospital:server:RespawnAtHospital', function(closestBed)
    local src = source
    local Player = WCore.Functions.GetPlayer(src)
    local meta = Player and Player.PlayerData.metadata or {}   -- ✅ هنا محمي
```

هذا السطر محمي فعلاً ✅ — لكن `سطر 304` و `سطر 314` يستخدمان `Player.Functions.ClearInventory()` مباشرة في فروع `Config.WipeInventoryOnRespawn`. مقبول عملياً (اللاعب متصل)، لكن غير متسق مع بقية الملف اللي يتحقق دائماً بـ `if not Player then return end`.

---

## التقييم

**المستوى: عالي.** الكومنتات تشرح **ليش** مو **ماذا** — وهذا يدل على مطوّر يفهم concurrency والأمان. الأمان على السيرفر متين، `bedGeneration` والتوافق مع أربع حقائب يدل على خبرة عملية.

**نقاط الضعف:** ثغرات أمنية صغيرة (المسافة في `takeSupplies`، lack of cleanup، تكرار الفاتورة)، handful من hardcodes متبقية من كود قديم، وتكرار `ApplyBleed`.

---

## أولويات الإصلاح

| # | المشكلة | الأولوية | الملف |
|---|---|---|---|
| 1 | مسار الاختبارات | فوري — الاختبارات ميتة | `tests/test_pharmacy.py`, `tests/test_pay.py` |
| 2 | مسافة `takeSupplies` | عالي — ثغرة أمنية | `server/main.lua` |
| 3 | cleanup `PlayerInjuries` | عالي — تسريب ذاكرة | `server/main.lua` |
| 4 | `SendToBed` فاتورة مكررة | عالي — استغلال مالي | `server/main.lua` |
| 5 | `SetDoctor` performance | متوسط | `server/main.lua` |
| 6 | hardcode 300 في `CanHelp` | متوسط | `client/laststand.lua` |
| 7 | `DispatchTimer * 4` (توثيق فقط — الحساب سليم) | منخفض | `config.lua` + `client/main.lua` |
| 8 | تكرار `ApplyBleed` | متوسط | `client/wounding.lua` |
| 9 | `SyncInjuries` مزدوج/ثلاثي | منخفض | `client/main.lua` |
| 10 | `severity` bounds | منخفض | `client/main.lua` |