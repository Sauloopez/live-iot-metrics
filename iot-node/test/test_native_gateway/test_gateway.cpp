// Native (PC) tests for the LoRa link: field node transport, custody in the LoRa gateway node
// and forwarding to the server, including a lossy radio end to end.
#include <unity.h>
#include <deque>
#include <map>
#include <set>
#include <vector>
#include "../test_native_lora/FakeCipher.h"
#include "../test_native_storage/InMemoryFileSystem.h"
#include "../../src/lora_field/infrastructure/LoraSyncTransport.h"
#include "../../src/lora_gateway/usecases/GatewayCustody.h"
#include "../../src/lora_gateway/usecases/GatewayForwarder.h"
#include "../../src/shared/infrastructure/storage/SegmentedMeasurementStore.h"
#include "../../src/shared/usecases/RemoteSync.h"

static const uint8_t MAC_A[6] = {0x02, 0x00, 0x00, 0x00, 0x00, 0xA1};
static const uint8_t MAC_B[6] = {0x02, 0x00, 0x00, 0x00, 0x00, 0xB2};
static const uint32_t NOW = 1762300000;

// --- Doubles ---

struct MemoryCounterStore : ICounterStore {
    uint32_t value = 0;
    uint32_t load() override { return value; }
    bool save(uint32_t v) override {
        value = v;
        return true;
    }
};

// Several nodes over one server, like LiveMetrics.Sync.Ingest: per MAC, only the measurement
// right after the watermark is accepted
class FakeServer : public ISyncTransport {
public:
    std::map<std::vector<uint8_t>, std::vector<Measurement>> stored;
    bool down = false;
    uint32_t exchanges = 0;

    bool exchange(const uint8_t* req, size_t len, uint8_t* resp, size_t cap, size_t* respLen) override {
        if (down) return false;
        exchanges++;
        std::vector<Measurement>& node = stored[std::vector<uint8_t>(req, req + 6)];
        const uint8_t* frame = req + 6;
        size_t frameLen = len - 6;
        TEST_ASSERT_EQUAL_HEX16(Crc16::compute(frame, frameLen - 2), frame[frameLen - 2] | (frame[frameLen - 1] << 8));

        size_t pos = SyncStream::HEADER_SIZE;
        for (uint8_t i = 0; i < frame[7]; i++) {
            Measurement m;
            size_t used = 0;
            MeasurementCodec::decode(frame + pos, frameLen - 2 - pos, &m, &used);
            pos += used;
            uint32_t watermark = node.empty() ? 0 : node.back().seq;
            if (m.seq == watermark + 1) node.push_back(m);
        }
        uint32_t watermark = node.empty() ? 0 : node.back().seq;
        TEST_ASSERT_GREATER_OR_EQUAL(8, cap);
        LoraPacket::writeU32(resp, watermark);
        LoraPacket::writeU32(resp + 4, NOW);
        *respLen = 8;
        return true;
    }

    const std::vector<Measurement>& of(const uint8_t mac[6]) { return stored[std::vector<uint8_t>(mac, mac + 6)]; }
};

// Gateway node with its own flash; reboot() keeps the flash and loses everything else
struct Gateway {
    FakeCipher cipher;
    InMemoryFileSystem fs;
    OriginStores* origins = nullptr;
    GatewayCustody* custody = nullptr;
    uint16_t epoch = 0;

    Gateway() { reboot(); }
    ~Gateway() {
        delete custody;
        delete origins;
    }

    void reboot() {
        delete custody;
        delete origins;
        epoch++;
        origins = new OriginStores(fs, "/o", 16);
        TEST_ASSERT_TRUE(origins->begin());
        custody = new GatewayCustody(cipher, *origins, epoch);
    }
};

// Radio between one field node and the gateway. Loses packets following a fixed pattern
class SimRadio : public IRadio {
public:
    Gateway& gateway;
    std::deque<std::vector<uint8_t>> inbox;
    uint32_t dataLossEvery = 0;  // 0 = never; n = every n-th DATA is lost
    uint32_t ackLossEvery = 0;
    std::set<uint32_t> lostData, lostAcks;  // numbers (from 1) of the packets lost on air
    uint32_t sent = 0, acks = 0;

    explicit SimRadio(Gateway& gateway) : gateway(gateway) {}

    bool send(const uint8_t* packet, size_t len) override {
        TEST_ASSERT_LESS_OR_EQUAL(LoraPacket::MAX_SIZE, len);
        sent++;
        if ((dataLossEvery && sent % dataLossEvery == 0) || lostData.count(sent)) return true;  // lost on air

        uint8_t ack[LoraPacket::MAX_SIZE];
        size_t ackLen = gateway.custody->handle(packet, len, NOW, ack, sizeof(ack));
        if (ackLen == 0) return true;
        acks++;
        if ((ackLossEvery && acks % ackLossEvery == 0) || lostAcks.count(acks)) return true;
        inbox.emplace_back(ack, ack + ackLen);
        return true;
    }

    bool receive(uint8_t* packet, size_t cap, size_t* len, uint32_t) override {
        if (inbox.empty()) return false;
        std::vector<uint8_t> p = inbox.front();
        inbox.pop_front();
        TEST_ASSERT_LESS_OR_EQUAL(cap, p.size());
        memcpy(packet, p.data(), p.size());
        *len = p.size();
        return true;
    }
};

static uint32_t waited = 0;
static void fakeWait(uint32_t ms) { waited += ms; }

// Field node: own flash, store, frame counter, LoRa transport and RemoteSync
struct FieldNode {
    uint8_t mac[6];
    FakeCipher cipher;
    InMemoryFileSystem fs;
    SegmentedMeasurementStore store;
    MemoryCounterStore nvs;
    FrameCounter counter;
    SimRadio radio;
    LoraSyncTransport transport;
    RemoteSync sync;

    FieldNode(const uint8_t m[6], Gateway& gateway)
        : store(fs, "/m", 16), counter(nvs), radio(gateway), transport(radio, cipher, counter, m, fakeWait),
          sync(m, RemoteSync::LORA_RECORDS_PER_FRAME) {
        memcpy(mac, m, 6);
        TEST_ASSERT_TRUE(store.open());
        counter.begin();
    }

    void measure(uint32_t n) {
        for (uint32_t i = 0; i < n; i++) {
            uint32_t seq = store.status().nextSeq;
            TEST_ASSERT_TRUE(store.record(NOW - 10000 + seq, seq % 3, seq * 0.5f));
        }
    }

    RemoteSync::Result syncOnce(uint32_t exchanges = 8) { return sync.run(store, transport, exchanges); }
};

// --- Helpers to build packets by hand ---

static FakeCipher cipher;

static std::vector<uint8_t> dataPacket(SegmentedMeasurementStore& source, uint32_t fromSeq, uint32_t count,
                                       const uint8_t mac[6], uint32_t counter) {
    SyncStream stream(8);
    stream.start(source, fromSeq, count);
    uint8_t frame[LoraPacket::MAX_PAYLOAD];
    size_t frameLen = 0;
    TEST_ASSERT_TRUE(stream.next(source, frame, sizeof(frame), &frameLen) == SyncStream::Output::Data);

    LoraPacket::Header h;
    h.type = LoraPacket::TYPE_DATA;
    memcpy(h.mac, mac, 6);
    h.counter = counter;
    std::vector<uint8_t> packet(LoraPacket::MAX_SIZE);
    packet.resize(LoraPacket::seal(cipher, h, frame, frameLen, packet.data(), packet.size()));
    return packet;
}

static size_t deliver(Gateway& gw, const std::vector<uint8_t>& packet, GatewayCustody::Result* r,
                      std::vector<uint8_t>* ackOut = nullptr) {
    uint8_t ack[LoraPacket::MAX_SIZE];
    size_t len = gw.custody->handle(packet.data(), packet.size(), NOW, ack, sizeof(ack), r);
    if (ackOut) ackOut->assign(ack, ack + len);
    return len;
}

static InMemoryFileSystem* sourceFs;
static SegmentedMeasurementStore* source;  // what a field node would have stored

void setUp(void) {
    waited = 0;
    sourceFs = new InMemoryFileSystem();
    source = new SegmentedMeasurementStore(*sourceFs, "/m", 16);
    source->open();
    for (int i = 0; i < 100; i++) source->record(NOW - 1000 + i, i % 4, i * 1.5f);
}

void tearDown(void) {
    delete source;
    delete sourceFs;
}

// --- Custody ---

void test_custody_stores_with_original_seq_and_acks(void) {
    Gateway gw;
    GatewayCustody::Result r;
    std::vector<uint8_t> ack;
    TEST_ASSERT_GREATER_THAN(0, deliver(gw, dataPacket(*source, 1, 8, MAC_A, 1), &r, &ack));
    TEST_ASSERT_TRUE(r.outcome == GatewayCustody::Outcome::Stored);
    TEST_ASSERT_EQUAL_UINT32(8, r.stored);
    TEST_ASSERT_EQUAL_UINT32(8, r.custodySeq);

    // The ACK answers this DATA: same MAC and counter, the gateway epoch, watermark and time
    LoraPacket::Header h;
    uint8_t payload[LoraPacket::MAX_PAYLOAD];
    size_t len = 0;
    TEST_ASSERT_TRUE(LoraPacket::open(cipher, ack.data(), ack.size(), &h, payload, sizeof(payload), &len) ==
                     LoraPacket::Status::Ok);
    TEST_ASSERT_EQUAL_UINT8(LoraPacket::TYPE_ACK, h.type);
    TEST_ASSERT_EQUAL_UINT8_ARRAY(MAC_A, h.mac, 6);
    TEST_ASSERT_EQUAL_UINT32(1, h.counter);
    TEST_ASSERT_EQUAL_UINT16(gw.epoch, h.epoch);
    TEST_ASSERT_EQUAL(8, len);
    TEST_ASSERT_EQUAL_UINT32(8, LoraPacket::readU32(payload));
    TEST_ASSERT_EQUAL_UINT32(NOW, LoraPacket::readU32(payload + 4));

    // Stored as the field node had them
    std::vector<Measurement> kept;
    gw.origins->find(MAC_A)->store->readFrom(1, 100, [&](const Measurement& m) {
        kept.push_back(m);
        return true;
    });
    TEST_ASSERT_EQUAL(8, kept.size());
    TEST_ASSERT_EQUAL_UINT32(1, kept[0].seq);
    TEST_ASSERT_EQUAL_UINT32(NOW - 1000, kept[0].ts);
    TEST_ASSERT_EQUAL_FLOAT(10.5f, kept[7].value);
}

void test_new_origin_continues_its_numbering(void) {
    Gateway gw;
    GatewayCustody::Result r;
    deliver(gw, dataPacket(*source, 50, 8, MAC_A, 1), &r);
    TEST_ASSERT_EQUAL_UINT32(8, r.stored);
    TEST_ASSERT_EQUAL_UINT32(57, r.custodySeq);

    StoreStatus s = gw.origins->find(MAC_A)->store->status();
    TEST_ASSERT_EQUAL_UINT32(49, s.ackedSeq);  // older data never reached this gateway
    TEST_ASSERT_EQUAL_UINT32(8, s.pending());
}

void test_resend_after_lost_ack_is_not_duplicated(void) {
    Gateway gw;
    GatewayCustody::Result r;
    deliver(gw, dataPacket(*source, 1, 8, MAC_A, 1), &r);
    TEST_ASSERT_GREATER_THAN(0, deliver(gw, dataPacket(*source, 1, 8, MAC_A, 2), &r));  // new counter
    TEST_ASSERT_EQUAL_UINT32(0, r.stored);
    TEST_ASSERT_EQUAL_UINT32(8, r.custodySeq);

    // Overlapping frame: only the new part is kept
    deliver(gw, dataPacket(*source, 5, 8, MAC_A, 3), &r);
    TEST_ASSERT_EQUAL_UINT32(4, r.stored);
    TEST_ASSERT_EQUAL_UINT32(12, r.custodySeq);
    TEST_ASSERT_EQUAL_UINT32(12, gw.origins->find(MAC_A)->store->status().pending());
}

void test_gap_is_not_stored(void) {
    Gateway gw;
    GatewayCustody::Result r;
    deliver(gw, dataPacket(*source, 1, 8, MAC_A, 1), &r);
    TEST_ASSERT_GREATER_THAN(0, deliver(gw, dataPacket(*source, 17, 8, MAC_A, 2), &r));
    TEST_ASSERT_EQUAL_UINT32(0, r.stored);
    TEST_ASSERT_EQUAL_UINT32(8, r.custodySeq);  // the field node goes back to 9
}

void test_replayed_and_invalid_packets_get_no_answer(void) {
    Gateway gw;
    GatewayCustody::Result r;
    std::vector<uint8_t> packet = dataPacket(*source, 1, 8, MAC_A, 5);
    TEST_ASSERT_GREATER_THAN(0, deliver(gw, packet, &r));

    TEST_ASSERT_EQUAL(0, deliver(gw, packet, &r));
    TEST_ASSERT_TRUE(r.outcome == GatewayCustody::Outcome::Replay);
    TEST_ASSERT_EQUAL(0, deliver(gw, dataPacket(*source, 9, 8, MAC_A, 4), &r));  // older counter
    TEST_ASSERT_TRUE(r.outcome == GatewayCustody::Outcome::Replay);

    std::vector<uint8_t> forged = dataPacket(*source, 9, 8, MAC_A, 6);
    forged[20] ^= 0x01;
    TEST_ASSERT_EQUAL(0, deliver(gw, forged, &r));
    TEST_ASSERT_TRUE(r.outcome == GatewayCustody::Outcome::BadPacket);

    FakeCipher otherKey(0x77);
    LoraPacket::Header h;
    h.type = LoraPacket::TYPE_DATA;
    memcpy(h.mac, MAC_B, 6);
    h.counter = 1;
    uint8_t frame[10] = {0}, raw[LoraPacket::MAX_SIZE];
    size_t len = LoraPacket::seal(otherKey, h, frame, sizeof(frame), raw, sizeof(raw));
    TEST_ASSERT_EQUAL(0, deliver(gw, std::vector<uint8_t>(raw, raw + len), &r));
    TEST_ASSERT_NULL(gw.origins->find(MAC_B));  // no store for strangers

    // A forged packet did not use up the real counter 6
    TEST_ASSERT_GREATER_THAN(0, deliver(gw, dataPacket(*source, 9, 8, MAC_A, 6), &r));
    TEST_ASSERT_EQUAL_UINT32(16, r.custodySeq);
}

void test_ack_packets_are_ignored_by_the_gateway(void) {
    Gateway gw;
    GatewayCustody::Result r;
    LoraPacket::Header h;
    h.type = LoraPacket::TYPE_ACK;
    memcpy(h.mac, MAC_A, 6);
    h.counter = 1;
    uint8_t payload[8] = {0}, raw[LoraPacket::MAX_SIZE];
    size_t len = LoraPacket::seal(cipher, h, payload, sizeof(payload), raw, sizeof(raw));
    TEST_ASSERT_EQUAL(0, deliver(gw, std::vector<uint8_t>(raw, raw + len), &r));
    TEST_ASSERT_TRUE(r.outcome == GatewayCustody::Outcome::NotData);
}

void test_custody_survives_gateway_reboot(void) {
    Gateway gw;
    GatewayCustody::Result r;
    deliver(gw, dataPacket(*source, 1, 8, MAC_A, 1), &r);
    deliver(gw, dataPacket(*source, 30, 8, MAC_B, 1), &r);

    gw.reboot();
    TEST_ASSERT_EQUAL(2, gw.origins->size());
    TEST_ASSERT_EQUAL_UINT32(8, gw.origins->find(MAC_A)->store->status().pending());
    TEST_ASSERT_EQUAL_UINT32(38, gw.origins->find(MAC_B)->store->status().nextSeq);

    deliver(gw, dataPacket(*source, 9, 8, MAC_A, 2), &r);
    TEST_ASSERT_EQUAL_UINT32(16, r.custodySeq);
}

// --- Forwarding ---

void test_forwarder_sends_each_origin_as_itself(void) {
    Gateway gw;
    GatewayCustody::Result r;
    for (uint32_t i = 0; i < 4; i++) deliver(gw, dataPacket(*source, 1 + i * 8, 8, MAC_A, i + 1), &r);
    deliver(gw, dataPacket(*source, 1, 8, MAC_B, 1), &r);

    FakeServer server;
    GatewayForwarder forwarder;
    GatewayForwarder::Result f = forwarder.run(*gw.origins, server, 8);
    TEST_ASSERT_FALSE(f.transportError);
    TEST_ASSERT_EQUAL_UINT32(NOW, f.serverTime);

    TEST_ASSERT_EQUAL(32, server.of(MAC_A).size());
    TEST_ASSERT_EQUAL(8, server.of(MAC_B).size());
    TEST_ASSERT_EQUAL_FLOAT(31 * 1.5f, server.of(MAC_A).back().value);
    TEST_ASSERT_EQUAL_UINT32(0, gw.origins->find(MAC_A)->store->status().pending());  // released
    TEST_ASSERT_EQUAL_UINT32(0, gw.origins->find(MAC_B)->store->status().pending());
}

void test_forwarder_keeps_custody_while_server_is_down(void) {
    Gateway gw;
    GatewayCustody::Result r;
    deliver(gw, dataPacket(*source, 1, 8, MAC_A, 1), &r);

    FakeServer server;
    server.down = true;
    GatewayForwarder forwarder;
    TEST_ASSERT_TRUE(forwarder.run(*gw.origins, server, 8).transportError);
    TEST_ASSERT_EQUAL_UINT32(8, gw.origins->find(MAC_A)->store->status().pending());

    server.down = false;
    forwarder.run(*gw.origins, server, 8);
    TEST_ASSERT_EQUAL(8, server.of(MAC_A).size());
}

// --- Field node transport ---

void test_field_node_releases_what_the_gateway_acked(void) {
    Gateway gw;
    FieldNode node(MAC_A, gw);
    node.measure(20);

    RemoteSync::Result res = node.syncOnce();
    TEST_ASSERT_TRUE(res.complete);
    TEST_ASSERT_EQUAL_UINT32(20, res.ackedSeq);
    TEST_ASSERT_EQUAL_UINT32(NOW, res.serverTime);  // the gateway hands out its time
    TEST_ASSERT_EQUAL_UINT32(0, node.store.status().pending());
    TEST_ASSERT_EQUAL_UINT32(20, gw.origins->find(MAC_A)->store->status().pending());
}

void test_field_node_retries_with_new_counter_and_backoff(void) {
    Gateway gw;
    FieldNode node(MAC_A, gw);
    node.measure(8);
    // 1st try: stored, ACK lost. 2nd try: DATA lost. 3rd try: a resend, ACK received
    node.radio.lostAcks = {1};
    node.radio.lostData = {2};

    RemoteSync::Result res = node.syncOnce(1);
    TEST_ASSERT_FALSE(res.transportError);
    TEST_ASSERT_EQUAL_UINT32(8, res.ackedSeq);
    TEST_ASSERT_EQUAL_UINT32(3, node.radio.sent);
    TEST_ASSERT_TRUE(waited >= 2 * 200 && waited <= 2 * 1500);  // two random waits

    uint32_t lastCounter = 0;
    TEST_ASSERT_EQUAL_UINT32(8, gw.origins->find(MAC_A)->store->status().pending());  // stored once
    TEST_ASSERT_EQUAL_UINT32(3, node.counter.next(&lastCounter) ? lastCounter - 1 : 0);  // 3 counters used
}

void test_field_node_gives_up_after_attempts(void) {
    Gateway gw;
    FieldNode node(MAC_A, gw);
    node.measure(8);
    node.radio.dataLossEvery = 1;  // nothing gets through

    RemoteSync::Result res = node.syncOnce();
    TEST_ASSERT_TRUE(res.transportError);
    TEST_ASSERT_EQUAL_UINT32(3, node.radio.sent);
    TEST_ASSERT_TRUE(waited >= 2 * 200 && waited <= 2 * 1500);  // two random waits
    TEST_ASSERT_EQUAL_UINT32(8, node.store.status().pending());  // kept for the next wake up
}

void test_field_node_ignores_foreign_acks(void) {
    Gateway gw;
    FieldNode node(MAC_A, gw);
    node.measure(8);

    // An ACK for another node and an old ACK of its own arrive before the real one
    LoraPacket::Header h;
    h.type = LoraPacket::TYPE_ACK;
    memcpy(h.mac, MAC_B, 6);
    h.counter = 1;
    uint8_t payload[8] = {0xFF, 0xFF, 0, 0, 0, 0, 0, 0}, raw[LoraPacket::MAX_SIZE];
    size_t len = LoraPacket::seal(cipher, h, payload, sizeof(payload), raw, sizeof(raw));
    node.radio.inbox.emplace_back(raw, raw + len);
    memcpy(h.mac, MAC_A, 6);
    h.counter = 999;
    len = LoraPacket::seal(cipher, h, payload, sizeof(payload), raw, sizeof(raw));
    node.radio.inbox.emplace_back(raw, raw + len);

    RemoteSync::Result res = node.syncOnce();
    TEST_ASSERT_EQUAL_UINT32(8, res.ackedSeq);  // not 0xFFFF
    TEST_ASSERT_TRUE(res.complete);
}

// --- End to end ---

void test_lossy_link_end_to_end(void) {
    Gateway gw;
    FakeServer server;
    GatewayForwarder forwarder;
    FieldNode a(MAC_A, gw), b(MAC_B, gw);
    a.radio.dataLossEvery = 3;
    a.radio.ackLossEvery = 4;
    b.radio.dataLossEvery = 5;
    b.radio.ackLossEvery = 2;

    // Several wake ups: measure, sync over LoRa; the gateway forwards when it has network
    for (int wake = 0; wake < 40; wake++) {
        if (wake < 10) {
            a.measure(13);
            b.measure(7);
        }
        a.syncOnce(4);
        b.syncOnce(4);
        server.down = wake % 3 == 0;  // intermittent WiFi at the gateway
        forwarder.run(*gw.origins, server, 4);
        if (wake == 12) gw.reboot();  // power loss at the gateway
    }
    server.down = false;
    for (int i = 0; i < 20; i++) forwarder.run(*gw.origins, server, 8);

    TEST_ASSERT_EQUAL_UINT32(0, a.store.status().pending());
    TEST_ASSERT_EQUAL_UINT32(0, b.store.status().pending());

    // The server got everything, once, in order and unchanged
    const std::vector<Measurement>& ma = server.of(MAC_A);
    const std::vector<Measurement>& mb = server.of(MAC_B);
    TEST_ASSERT_EQUAL(130, ma.size());
    TEST_ASSERT_EQUAL(70, mb.size());
    for (uint32_t i = 0; i < ma.size(); i++) {
        TEST_ASSERT_EQUAL_UINT32(i + 1, ma[i].seq);
        TEST_ASSERT_EQUAL_FLOAT((i + 1) * 0.5f, ma[i].value);
    }
    TEST_ASSERT_EQUAL_UINT32(0, gw.origins->find(MAC_A)->store->status().pending());
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_custody_stores_with_original_seq_and_acks);
    RUN_TEST(test_new_origin_continues_its_numbering);
    RUN_TEST(test_resend_after_lost_ack_is_not_duplicated);
    RUN_TEST(test_gap_is_not_stored);
    RUN_TEST(test_replayed_and_invalid_packets_get_no_answer);
    RUN_TEST(test_ack_packets_are_ignored_by_the_gateway);
    RUN_TEST(test_custody_survives_gateway_reboot);
    RUN_TEST(test_forwarder_sends_each_origin_as_itself);
    RUN_TEST(test_forwarder_keeps_custody_while_server_is_down);
    RUN_TEST(test_field_node_releases_what_the_gateway_acked);
    RUN_TEST(test_field_node_retries_with_new_counter_and_backoff);
    RUN_TEST(test_field_node_gives_up_after_attempts);
    RUN_TEST(test_field_node_ignores_foreign_acks);
    RUN_TEST(test_lossy_link_end_to_end);
    return UNITY_END();
}
