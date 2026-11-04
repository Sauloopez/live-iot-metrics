#ifndef STORAGE_TASK_H
#define STORAGE_TASK_H

#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/event_groups.h>
#include <freertos/queue.h>
#include <freertos/semphr.h>
#include <freertos/task.h>
#include "../../domain/repositories/IMeasurementStore.h"

// FreeRTOS task that owns the measurement store.
//
// Sensor readers only enqueue values (never block on the file system); this task writes them.
// Other tasks (USB sync, radio) use the store through withStore(), which holds the store mutex
// so a stream or an ack never runs in the middle of a write.
class StorageTask {
public:
    struct Pending {
        uint32_t ts;
        uint16_t sensorId;
        float value;
    };

    explicit StorageTask(IMeasurementStore& store) : store(store) {}

    bool begin(UBaseType_t queueLength = 32, UBaseType_t priority = 2, BaseType_t core = 1) {
        queue = xQueueCreate(queueLength, sizeof(Pending));
        mutex = xSemaphoreCreateMutex();
        events = xEventGroupCreate();
        if (!queue || !mutex || !events) return false;

        xEventGroupSetBits(events, IDLE_BIT);
        return xTaskCreatePinnedToCore(&StorageTask::run, "storage", 4096, this, priority, &handle, core) ==
               pdPASS;
    }

    // Called by sensor readers. Returns false if the queue stayed full for `wait` ticks.
    bool enqueue(uint32_t ts, uint16_t sensorId, float value, TickType_t wait = 0) {
        Pending item{ts, sensorId, value};
        xEventGroupClearBits(events, IDLE_BIT);
        if (xQueueSend(queue, &item, wait) == pdTRUE) return true;
        if (uxQueueMessagesWaiting(queue) == 0) xEventGroupSetBits(events, IDLE_BIT);
        return false;
    }

    // Runs `fn(store)` with exclusive access to the store.
    template <typename Fn>
    bool withStore(Fn fn, TickType_t wait = portMAX_DELAY) {
        if (xSemaphoreTake(mutex, wait) != pdTRUE) return false;
        fn(store);
        xSemaphoreGive(mutex);
        return true;
    }

    // Blocks until every queued value is written; used before going to deep sleep.
    bool waitUntilIdle(TickType_t timeout) {
        return (xEventGroupWaitBits(events, IDLE_BIT, pdFALSE, pdTRUE, timeout) & IDLE_BIT) != 0;
    }

    uint32_t failedWrites() const { return failed; }

private:
    static const EventBits_t IDLE_BIT = BIT0;

    IMeasurementStore& store;
    QueueHandle_t queue = nullptr;
    SemaphoreHandle_t mutex = nullptr;
    EventGroupHandle_t events = nullptr;
    TaskHandle_t handle = nullptr;
    volatile uint32_t failed = 0;

    static void run(void* arg) {
        StorageTask* self = static_cast<StorageTask*>(arg);
        Pending item;
        for (;;) {
            if (xQueueReceive(self->queue, &item, portMAX_DELAY) != pdTRUE) continue;

            xSemaphoreTake(self->mutex, portMAX_DELAY);
            if (!self->store.record(item.ts, item.sensorId, item.value)) self->failed++;
            xSemaphoreGive(self->mutex);

            if (uxQueueMessagesWaiting(self->queue) == 0) xEventGroupSetBits(self->events, IDLE_BIT);
        }
    }
};

#endif // STORAGE_TASK_H
