// Native (PC) tests for the wake cycle, battery and clock logic: `pio test -e native`.
#include <unity.h>
#include "../../src/shared/domain/entities/BatteryLevel.h"
#include "../../src/shared/infrastructure/time/Ds3231Codec.h"
#include "../../src/shared/usecases/WakeCycle.h"

using WakeCycle::Action;
using WakeCycle::WakeReason;

void setUp(void) {}
void tearDown(void) {}

// --- Wake decision ---

void test_timer_wake_measures(void) {
    TEST_ASSERT_TRUE(WakeCycle::decide(WakeReason::Timer, true) == Action::Measure);
}

void test_operator_wakes_enter_service_mode(void) {
    TEST_ASSERT_TRUE(WakeCycle::decide(WakeReason::PowerOn, true) == Action::Service);
    TEST_ASSERT_TRUE(WakeCycle::decide(WakeReason::ServiceButton, true) == Action::Service);
}

void test_without_sensors_the_node_stays_reachable(void) {
    TEST_ASSERT_TRUE(WakeCycle::decide(WakeReason::Timer, false) == Action::Service);
}

// --- Wake schedule ---

void test_wakes_are_aligned_to_the_interval_grid(void) {
    // 10:07:30 with a 15 min interval -> next slot 10:15:00 (7.5 min later)
    uint32_t now = 1762164450;  // 2025-11-03 10:07:30 UTC
    TEST_ASSERT_EQUAL_UINT32(450, WakeCycle::secondsUntilNextWake(now, true, 900));
}

void test_a_slot_too_close_is_skipped(void) {
    uint32_t slot = 1762164900;  // exactly 10:15:00
    TEST_ASSERT_EQUAL_UINT32(900, WakeCycle::secondsUntilNextWake(slot, true, 900));
    TEST_ASSERT_EQUAL_UINT32(901, WakeCycle::secondsUntilNextWake(slot - 1, true, 900));
}

void test_without_clock_the_plain_interval_is_used(void) {
    TEST_ASSERT_EQUAL_UINT32(900, WakeCycle::secondsUntilNextWake(12345, false, 900));
}

void test_service_mode_expires_after_idle_time_even_across_millis_overflow(void) {
    TEST_ASSERT_FALSE(WakeCycle::serviceModeExpired(1000 + 299999, 1000, 300000));
    TEST_ASSERT_TRUE(WakeCycle::serviceModeExpired(1000 + 300000, 1000, 300000));
    // millis() wrapped around after the last activity
    TEST_ASSERT_FALSE(WakeCycle::serviceModeExpired(100, UINT32_MAX - 100, 300000));
}

// --- Battery ---

void test_battery_percent_follows_the_cell_curve(void) {
    TEST_ASSERT_EQUAL_UINT8(100, BatteryLevel::percentFromMillivolts(4250));
    TEST_ASSERT_EQUAL_UINT8(100, BatteryLevel::percentFromMillivolts(4200));
    TEST_ASSERT_EQUAL_UINT8(50, BatteryLevel::percentFromMillivolts(3800));
    TEST_ASSERT_EQUAL_UINT8(55, BatteryLevel::percentFromMillivolts(3825));
    TEST_ASSERT_EQUAL_UINT8(0, BatteryLevel::percentFromMillivolts(3300));
    TEST_ASSERT_EQUAL_UINT8(0, BatteryLevel::percentFromMillivolts(2900));
}

void test_battery_voltage_from_divider(void) {
    // 100k/100k divider halves the voltage
    TEST_ASSERT_EQUAL_UINT32(3900, BatteryLevel::batteryMillivolts(1950, 100000, 100000));
    TEST_ASSERT_EQUAL_UINT32(0, BatteryLevel::batteryMillivolts(1950, 100000, 0));
}

// --- DS3231 ---

void test_bcd_conversion(void) {
    TEST_ASSERT_EQUAL_HEX8(0x59, Ds3231Codec::toBcd(59));
    TEST_ASSERT_EQUAL_UINT8(59, Ds3231Codec::fromBcd(0x59));
}

void test_ds3231_registers_round_trip(void) {
    const uint32_t samples[] = {946684800u /* 2000-01-01 */, 951782400u /* 2000-02-29 */,
                                1762164450u, 4102444799u /* 2099-12-31 23:59:59 */};
    for (uint32_t unixTime : samples) {
        uint8_t regs[7];
        Ds3231Codec::encode(unixTime, regs);
        uint32_t back = 0;
        TEST_ASSERT_TRUE(Ds3231Codec::decode(regs, &back));
        TEST_ASSERT_EQUAL_UINT32(unixTime, back);
    }
}

void test_ds3231_known_register_values(void) {
    uint8_t regs[7];
    Ds3231Codec::encode(1762164450u, regs);  // 2025-11-03 10:07:30, a Monday
    TEST_ASSERT_EQUAL_HEX8(0x30, regs[0]);
    TEST_ASSERT_EQUAL_HEX8(0x07, regs[1]);
    TEST_ASSERT_EQUAL_HEX8(0x10, regs[2]);
    TEST_ASSERT_EQUAL_UINT8(2, regs[3]);  // 1 = Sunday
    TEST_ASSERT_EQUAL_HEX8(0x03, regs[4]);
    TEST_ASSERT_EQUAL_HEX8(0x11, regs[5]);
    TEST_ASSERT_EQUAL_HEX8(0x25, regs[6]);
}

void test_ds3231_twelve_hour_mode_and_invalid_registers(void) {
    // 2025-11-03 10:07:30 PM in 12-hour mode -> 22:07:30
    uint8_t regs[7] = {0x30, 0x07, 0x40 | 0x20 | 0x10, 2, 0x03, 0x11, 0x25};
    uint32_t unixTime = 0;
    TEST_ASSERT_TRUE(Ds3231Codec::decode(regs, &unixTime));
    TEST_ASSERT_EQUAL_UINT32(1762164450u + 12 * 3600, unixTime);

    uint8_t bad[7] = {0x30, 0x07, 0x10, 2, 0x00, 0x11, 0x25};  // day 0
    TEST_ASSERT_FALSE(Ds3231Codec::decode(bad, &unixTime));
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_timer_wake_measures);
    RUN_TEST(test_operator_wakes_enter_service_mode);
    RUN_TEST(test_without_sensors_the_node_stays_reachable);
    RUN_TEST(test_wakes_are_aligned_to_the_interval_grid);
    RUN_TEST(test_a_slot_too_close_is_skipped);
    RUN_TEST(test_without_clock_the_plain_interval_is_used);
    RUN_TEST(test_service_mode_expires_after_idle_time_even_across_millis_overflow);
    RUN_TEST(test_battery_percent_follows_the_cell_curve);
    RUN_TEST(test_battery_voltage_from_divider);
    RUN_TEST(test_bcd_conversion);
    RUN_TEST(test_ds3231_registers_round_trip);
    RUN_TEST(test_ds3231_known_register_values);
    RUN_TEST(test_ds3231_twelve_hour_mode_and_invalid_registers);
    return UNITY_END();
}
