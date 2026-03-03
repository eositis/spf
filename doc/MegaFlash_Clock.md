# MegaFlash Clock Support - Design Notes

This document captures the reasoning and design decisions behind adding MegaFlash clock support to SPF.

## Background

**MegaFlash** is an internal storage device for Apple IIc/IIc+ computers ([ThomasFok/MegaFlash](https://github.com/ThomasFok/MegaFlash)). It includes:
- Flash storage (128MB/256MB)
- Real-time clock with ProDOS driver
- NTP time sync capability

SPF's benchmark feature requires second-resolution timing. The standard ProDOS clock interface only provides minute resolution, so SPF uses a compatibility layer that detects and uses various hardware clocks directly.

## Research Process

1. **Identification**: MegaFlash was identified from the GitHub repo. The README lists "Real Time Clock with ProDOS clock driver" as a feature.

2. **Architecture**: MegaFlash is IIc/IIc+ only—it replaces the system ROM. Unlike slot-based cards (Thunderclock), it uses fixed I/O addresses $C0C0-$C0C3. Activation is handled in MegaFlash ROM; SPF does not perform the magic address sequence—it only checks for presence and reads the time.

3. **API Discovery**: From `common/defines.inc` and `firmware/megaflash.s`:
   - I/O: `cmdreg`/`statusreg`=$C0C0, `paramreg`=$C0C1, `datareg`=$C0C2, `idreg`=$C0C3
   - `CMD_GETDEVINFO` ($10) returns signature bytes $88, $74 in paramreg for detection
   - `CMD_GETPRODOS25TIME` ($18) returns 6-byte ProDOS 2.5 timestamp (includes seconds)

4. **Time Format**: From `pico/rtc.c` and `pico/cmdhandler.c`:
   - ProDOS legacy (4 bytes): date_lo, date_hi, minute, hour — **no seconds**
   - ProDOS 2.5 (6 bytes): t4ms, second, time_lo, time_hi, date_lo, date_hi
   - The time word: `time = mday<<11 | hour<<6 | min` (min=bits 0-5, hour=bits 6-10, mday=bits 11-15)

## Design Decisions

### 1. Detection Order

MegaFlash is checked **after** ROMX and **before** slotted clocks. Rationale:
- IIgs and NoSlotClock are checked first (common)
- ROMX is another "replacement" device
- MegaFlash (IIc-specific) before generic slotted clocks
- Thunderclock remains last for slot-based detection

### 2. ProDOS 2.5 vs ProDOS Legacy Format

We use `CMD_GETPRODOS25TIME` exclusively because:
- SPF needs **seconds** for elapsed-time benchmarks
- ProDOS legacy format only provides hour and minute
- ProDOS 2.5 format includes the second byte

### 3. Bit Extraction for Hour and Minute

The time word layout: `[mday:5][hour:5][min:6]`

- **Minutes**: `time & $3F` (low 6 bits)
- **Hours**: `(time >> 6) & $1F` (next 5 bits)

Decomposed for 6502:
- `hour_lo2 = (time_lo >> 6)` — bits 6–7 of time_lo become bits 0–1 of hour
- `hour_hi3 = (time_hi & $07) << 2` — bits 0–2 of time_hi (time bits 8–10) become bits 2–4 of hour
- `hour = hour_lo2 | hour_hi3` (5 bits, 0–23)

### 4. Hundredths of Seconds

MegaFlash provides `t4ms` (0–249, units of 4ms), so hundredths could be approximated. We use 0 for consistency with other clocks (GS, ROMX, Thunderclock) that don't expose sub-second resolution.

### 5. Error Handling

- **Detection timeout**: If the busy flag stays set for 100 polls, we assume no MegaFlash.
- **GetTime error**: If the status register error bit is set after the time command, we skip updating TimeNow and return (leaving prior values).

### 6. RTC Not Initialized

If MegaFlash's RTC has never been set (no NTP, no manual set), the firmware returns all zeros. SPF will show 00:00:00 and benchmarks would report ~0 elapsed time. This is a user configuration issue; we document it in the README.

## Implementation Notes

- **MFTime buffer**: 4 bytes for temp storage during extraction. [0] holds intermediate hour bits, [1]=sec, [2–3]=time word.
- **Activation**: Handled in MegaFlash ROM; SPF does not perform the magic address sequence.
