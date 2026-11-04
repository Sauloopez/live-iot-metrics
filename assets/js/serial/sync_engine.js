// Drives a data extraction from the node to the server with credit based flow control
// (docs/tundra/PLAN.md, section 6.1).
//
//   node --DATA frames--> engine --"sync_chunk" (batched records)--> server
//   node <--sync credit {ack, credit}-- engine <--reply {acked_seq}-- server
//
// The node never sends more than the granted credit and the engine renews it only as the
// server confirms, so memory is bounded on the three sides. Only the server confirms: the
// node releases nothing that is not stored in the database.

const WINDOW = 256; // measurements in flight (sent by the node, not yet confirmed)
const BATCH = 64; // measurements per "sync_chunk"
const BATCH_DELAY_MS = 200; // flush a partial batch after this pause
const MAX_RESTARTS = 5;

const toBase64 = (bytes) => {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
};

export class SyncEngine {
  // send(command) -> Promise<response>, push(event, payload) -> Promise<reply>, log(text)
  constructor({ send, push, log }) {
    this.send = send;
    this.push = push;
    this.log = log;
    this.state = null;
  }

  get running() {
    return this.state !== null;
  }

  // `acked` is the server watermark: the node may still hold data up to it
  async start({ acked }) {
    this.state = {
      acked,
      expected: acked + 1,
      batches: [],
      batchCount: 0,
      timer: null,
      inflight: 0,
      ended: false,
      restarting: false,
      restarts: 0,
      lastSeq: null,
    };
    // Lets the node release what the server already has, then starts the stream
    if (acked > 0) await this.send({ command: "sync", data: { action: "credit", ack: acked, credit: 0 } });
    await this.send({ command: "sync", data: { action: "stream", from: acked + 1, credit: WINDOW } });
  }

  async stop(reason = null) {
    if (!this.state) return;
    clearTimeout(this.state.timer);
    this.state = null;
    await this.send({ command: "sync", data: { action: "stop" } }).catch(() => {});
    if (reason) await this.push("sync_failed", { message: reason });
  }

  onFrame(frame) {
    const s = this.state;
    if (!s || s.restarting) return;

    if (!frame.valid) return this.restart(`damaged frame (${frame.reason})`);
    if (frame.firstSeq !== s.expected) return this.restart(`missing data before seq ${frame.firstSeq}`);

    s.batches.push(frame.records);
    s.batchCount += frame.count;
    s.expected += frame.count;

    if (s.batchCount >= BATCH) {
      this.flush();
    } else {
      clearTimeout(s.timer);
      s.timer = setTimeout(() => this.flush(), BATCH_DELAY_MS);
    }
  }

  onStreamEnd(lastSeq) {
    const s = this.state;
    if (!s || s.restarting) return;
    s.ended = true;
    s.lastSeq = lastSeq;
    this.flush();
    this.maybeFinish();
  }

  flush() {
    const s = this.state;
    if (!s) return;
    clearTimeout(s.timer);
    if (s.batchCount === 0) return;

    const size = s.batches.reduce((n, b) => n + b.length, 0);
    const records = new Uint8Array(size);
    let offset = 0;
    for (const b of s.batches) {
      records.set(b, offset);
      offset += b.length;
    }
    const count = s.batchCount;
    s.batches = [];
    s.batchCount = 0;
    s.inflight++;

    this.push("sync_chunk", { records: toBase64(records), count }).then((reply) => this.onChunkReply(reply));
  }

  async onChunkReply(reply) {
    const s = this.state;
    if (!s) return;
    s.inflight--;

    if (reply.error) return this.stop(`the server rejected the data: ${reply.error}`);

    const confirmed = reply.acked_seq - s.acked;
    s.acked = reply.acked_seq;
    if (confirmed > 0) {
      await this.send({ command: "sync", data: { action: "credit", ack: s.acked, credit: confirmed } });
    }

    if (s.restarting && s.inflight === 0) return this.resume();
    this.maybeFinish();
  }

  // Stops the stream and starts again right after the last confirmed measurement
  async restart(reason) {
    const s = this.state;
    if (!s || s.restarting) return;
    if (++s.restarts > MAX_RESTARTS) return this.stop(`too many transmission errors (${reason})`);

    this.log(`Sync: ${reason}; resuming from the last confirmed measurement`);
    s.restarting = true;
    clearTimeout(s.timer);
    s.batches = [];
    s.batchCount = 0;
    await this.send({ command: "sync", data: { action: "stop" } }).catch(() => {});
    if (s.inflight === 0) await this.resume();
  }

  async resume() {
    const s = this.state;
    if (!s) return;
    s.restarting = false;
    s.ended = false;
    s.expected = s.acked + 1;
    await this.send({ command: "sync", data: { action: "stream", from: s.expected, credit: WINDOW } });
  }

  async maybeFinish() {
    const s = this.state;
    if (!s || !s.ended || s.inflight > 0 || s.batchCount > 0) return;
    if (s.lastSeq !== null && s.acked < s.lastSeq) return this.restart("the server did not confirm everything");

    this.state = null;
    // Corrects the node clock on every visit (only nodes with a clock accept it)
    await this.send({ command: "time", data: { action: "set", ts: Math.floor(Date.now() / 1000) } }).catch(() => {});
    await this.push("sync_done", { acked_seq: s.acked });
  }
}
