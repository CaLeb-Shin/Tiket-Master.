const test = require("node:test");
const assert = require("node:assert/strict");

const {
  NaverTicketLogicError,
  buildMobileTicketPublicPayload,
  evaluateCancelOrderStatus,
  parseNaverOrderCreateInput,
} = require("../lib/naver_ticket_logic.js");

test("parseNaverOrderCreateInput trims values and normalizes quantity", () => {
  const parsed = parseNaverOrderCreateInput({
    eventId: "  event-1  ",
    naverOrderId: " NAVER-001 ",
    buyerName: " 홍길동 ",
    buyerPhone: " 010-1111-2222 ",
    productName: " 봄 공연 ",
    seatGrade: " R ",
    quantity: "2",
    memo: "  현장 수령  ",
    dryRun: true,
  });

  assert.deepEqual(parsed, {
    eventId: "event-1",
    naverOrderId: "NAVER-001",
    buyerName: "홍길동",
    buyerPhone: "010-1111-2222",
    productName: "봄 공연",
    seatGrade: "R",
    quantity: 2,
    orderDate: undefined,
    memo: "현장 수령",
    dryRun: true,
  });
});

test("parseNaverOrderCreateInput rejects missing required fields", () => {
  assert.throws(
    () => parseNaverOrderCreateInput({ quantity: 0 }),
    (error) => {
      assert.ok(error instanceof NaverTicketLogicError);
      assert.equal(error.code, "invalid-argument");
      assert.equal(error.message, "필수 필드가 누락되었거나 수량이 올바르지 않습니다");
      return true;
    },
  );
});

test("evaluateCancelOrderStatus keeps confirmed orders cancellable", () => {
  assert.deepEqual(evaluateCancelOrderStatus("confirmed"), {
    alreadyCancelled: false,
  });
});

test("evaluateCancelOrderStatus returns idempotent result for already cancelled bot requests", () => {
  assert.deepEqual(evaluateCancelOrderStatus("cancelled", true), {
    alreadyCancelled: true,
    message: "이미 취소된 주문",
  });
});

test("evaluateCancelOrderStatus throws for already cancelled admin requests", () => {
  assert.throws(
    () => evaluateCancelOrderStatus("cancelled", false),
    (error) => {
      assert.ok(error instanceof NaverTicketLogicError);
      assert.equal(error.code, "failed-precondition");
      assert.equal(error.message, "이미 취소된 주문입니다");
      return true;
    },
  );
});

test("buildMobileTicketPublicPayload hides seat info before reveal and sorts siblings", () => {
  const payload = buildMobileTicketPublicPayload({
    ticketId: "ticket-main",
    ticket: {
      eventId: "event-1",
      naverOrderId: "order-1",
      seatGrade: "VIP",
      seatInfo: "1층 A블록 1열 1번",
      seatNumber: "1",
      buyerName: "예매자",
      buyerPhone: "01012341234",
      recipientName: null,
      status: "active",
      entryNumber: 2,
      qrVersion: 3,
      entryCheckedInAt: null,
    },
    event: {
      title: "테스트 공연",
      venueName: "세종문화회관",
      venueAddress: "서울",
      revealAt: "2026-03-08T12:00:00.000Z",
      startAt: "2026-03-08T14:00:00.000Z",
      pamphletUrls: [],
    },
    now: new Date("2026-03-08T11:00:00.000Z"),
    siblingDocs: [
      {
        id: "ticket-3",
        data: {
          eventId: "event-1",
          naverOrderId: "order-1",
          seatGrade: "VIP",
          seatInfo: "1층 A블록 1열 3번",
          seatNumber: "3",
          buyerName: "예매자",
          buyerPhone: "01012341234",
          recipientName: "친구",
          status: "used",
          entryNumber: 3,
          qrVersion: 1,
          entryCheckedInAt: "2026-03-08T13:10:00.000Z",
        },
      },
      {
        id: "ticket-1",
        data: {
          eventId: "event-1",
          naverOrderId: "order-1",
          seatGrade: "VIP",
          seatInfo: "1층 A블록 1열 2번",
          seatNumber: "2",
          buyerName: "예매자",
          buyerPhone: "01012341234",
          recipientName: null,
          status: "cancelled",
          entryNumber: 1,
          qrVersion: 1,
          entryCheckedInAt: null,
        },
      },
    ],
  });

  assert.equal(payload.isRevealed, false);
  assert.equal(payload.ticket.displayStatus, "beforeReveal");
  assert.equal(payload.ticket.displayStatusLabel, "공개 전");
  assert.equal(payload.ticket.seatInfo, null);
  assert.equal(payload.ticket.seatNumber, null);
  assert.equal(payload.ticket.buyerPhoneLast4, "1234");
  assert.deepEqual(
    payload.siblings.map((sibling) => [sibling.id, sibling.displayStatus, sibling.displayStatusLabel]),
    [
      ["ticket-1", "cancelled", "취소됨"],
      ["ticket-3", "used", "사용 완료"],
    ],
  );
});
