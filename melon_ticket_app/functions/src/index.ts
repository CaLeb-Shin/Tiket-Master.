import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import * as jwt from "jsonwebtoken";
import sharp from "sharp";
import Anthropic from "@anthropic-ai/sdk";
import {
  buildMobileTicketPublicPayload,
  evaluateCancelOrderStatus,
  NaverTicketLogicError,
  type ParsedNaverOrderCreateInput,
  parseNaverOrderCreateInput,
} from "./naver_ticket_logic";

admin.initializeApp();
const db = admin.firestore();

// JWT 시크릿 (실제 운영 시 환경 변수로 관리)
const JWT_SECRET = process.env.JWT_SECRET || "melon-ticket-secret-key-change-in-production";
const QR_TOKEN_EXPIRY = 120; // 2분
// 취소 수수료 규정 (실제 서비스 기준)
// - 예매 후 7일 이내: 무료취소
// - 예매 후 8일 ~ 관람일 10일 전: 공연권 4000원 / 입장권 2000원 (최대 10%)
// - 관람일 9~7일 전: 10%
// - 관람일 6~3일 전: 20%
// - 관람일 2~1일 전: 30%
// - 관람 당일: 취소 불가
const PERFORMANCE_CATEGORIES = ["콘서트", "뮤지컬", "클래식", "오페라", "발레"];
// 위 카테고리는 공연권(4000원), 나머지(연극, 전시 등)는 입장권(2000원)

function calculateCancelFee(
  unitPrice: number,
  orderCreatedAt: Date,
  eventStartAt: Date,
  category: string | null,
  now: Date
): { refundRate: number; cancelFee: number; policy: string } {
  const daysSinceOrder = (now.getTime() - orderCreatedAt.getTime()) / (1000 * 60 * 60 * 24);
  const daysBeforeEvent = (eventStartAt.getTime() - now.getTime()) / (1000 * 60 * 60 * 24);

  // 관람 당일: 취소 불가
  if (daysBeforeEvent < 0) {
    return { refundRate: 0, cancelFee: unitPrice, policy: "관람일 이후 취소 불가" };
  }

  // 관람 당일 (0일 전)
  if (daysBeforeEvent < 1) {
    return { refundRate: 0, cancelFee: unitPrice, policy: "관람 당일 취소 불가" };
  }

  // 예매 후 7일 이내: 무료취소
  if (daysSinceOrder <= 7) {
    return { refundRate: 1, cancelFee: 0, policy: "예매 후 7일 이내 무료취소" };
  }

  // 관람일 2~1일 전: 30%
  if (daysBeforeEvent < 3) {
    const fee = Math.round(unitPrice * 0.3);
    return { refundRate: 0.7, cancelFee: fee, policy: "관람일 2일 전~1일 전 (30%)" };
  }

  // 관람일 6~3일 전: 20%
  if (daysBeforeEvent < 7) {
    const fee = Math.round(unitPrice * 0.2);
    return { refundRate: 0.8, cancelFee: fee, policy: "관람일 6일 전~3일 전 (20%)" };
  }

  // 관람일 9~7일 전: 10%
  if (daysBeforeEvent < 10) {
    const fee = Math.round(unitPrice * 0.1);
    return { refundRate: 0.9, cancelFee: fee, policy: "관람일 9일 전~7일 전 (10%)" };
  }

  // 예매 후 8일 ~ 관람일 10일 전: 정액 수수료
  const isPerformance = PERFORMANCE_CATEGORIES.includes(category ?? "");
  const flatFee = isPerformance ? 4000 : 2000;
  const maxFee = Math.round(unitPrice * 0.1);
  const fee = Math.min(flatFee, maxFee);
  return {
    refundRate: (unitPrice - fee) / unitPrice,
    cancelFee: fee,
    policy: `예매 후 8일 이상 (${isPerformance ? "공연권" : "입장권"} ${flatFee.toLocaleString()}원)`,
  };
}

/**
 * 8자리 영숫자 추천 코드 생성 (혼동 문자 제외)
 */
function generateReferralCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < 8; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

/**
 * 유니크한 추천 코드 생성 (Firestore에서 중복 체크)
 */
async function generateUniqueReferralCode(): Promise<string> {
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = generateReferralCode();
    const existing = await db
      .collection("users")
      .where("referralCode", "==", code)
      .limit(1)
      .get();
    if (existing.empty) return code;
  }
  // Fallback: timestamp suffix
  return generateReferralCode() + Date.now().toString(36).slice(-2).toUpperCase();
}

type SeatDoc = {
  id: string;
  block: string;
  floor: string;
  row?: string;
  number: number;
  seatKey?: string;
  [key: string]: any;
};

async function getUserRole(uid: string): Promise<string> {
  const userDoc = await db.collection("users").doc(uid).get();
  return (userDoc.data()?.role as string | undefined) ?? "user";
}

async function assertAdmin(uid?: string): Promise<string> {
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
  }
  const role = (await getUserRole(uid)).toLowerCase();
  if (role !== "admin" && role !== "superadmin") {
    throw new functions.https.HttpsError("permission-denied", "관리자 권한이 필요합니다");
  }
  return uid;
}

async function assertStaffOrAdmin(uid?: string): Promise<string> {
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
  }
  const role = (await getUserRole(uid)).toLowerCase();
  if (role !== "admin" && role !== "superadmin" && role !== "staff") {
    throw new functions.https.HttpsError("permission-denied", "스태프 권한이 필요합니다");
  }
  return uid;
}

type CheckinStage = "entry" | "intermission";
type PublicMobileTicketStatus = "active" | "used" | "cancelled";

function normalizeCheckinStage(value: unknown): CheckinStage {
  return value === "intermission" ? "intermission" : "entry";
}

function normalizeMobileTicketStatus(value: unknown): PublicMobileTicketStatus {
  if (value === "used") {
    return "used";
  }
  if (value === "canceled" || value === "cancelled") {
    return "cancelled";
  }
  return "active";
}

function toDate(value: any): Date | null {
  if (!value) return null;
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function isEventRevealed(event: any, now: Date = new Date()): boolean {
  const revealAt = toDate(event?.revealAt);
  return revealAt == null || now >= revealAt;
}

// ============================================================
// 동적 OG 태그 (소셜 미디어 공유 미리보기)
// ============================================================
export const ogMeta = functions.https.onRequest(async (req, res) => {
  const match = req.path.match(/^\/event\/([a-zA-Z0-9]+)/);
  if (!match) {
    res.redirect("/");
    return;
  }

  const eventId = match[1];
  const eventDoc = await db.collection("events").doc(eventId).get();

  if (!eventDoc.exists) {
    res.redirect("/");
    return;
  }

  const event = eventDoc.data()!;
  const title = event.title ?? "멜론티켓 공연";
  const description = event.description
    ? (event.description as string).substring(0, 150)
    : "AI 좌석 추천 · 360° 시야 보기 · 모바일 스마트 티켓";
  const imageUrl = event.imageUrl ?? "";
  const siteUrl = `https://melonticket-web-20260216.vercel.app/event/${eventId}`;
  const dateStr = event.startAt
    ? new Date((event.startAt as admin.firestore.Timestamp).toDate()).toLocaleDateString("ko-KR")
    : "";
  const venue = event.venueName ?? "";

  const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>${title} - 멜론티켓</title>
  <meta name="description" content="${description}">
  <meta property="og:type" content="website">
  <meta property="og:title" content="${title}">
  <meta property="og:description" content="${dateStr ? dateStr + " · " : ""}${venue ? venue + " · " : ""}${description}">
  <meta property="og:image" content="${imageUrl}">
  <meta property="og:url" content="${siteUrl}">
  <meta property="og:site_name" content="멜론티켓">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${title}">
  <meta name="twitter:description" content="${description}">
  <meta name="twitter:image" content="${imageUrl}">
  <meta http-equiv="refresh" content="0;url=${siteUrl}">
</head>
<body>
  <p>리디렉션 중... <a href="${siteUrl}">${title}</a></p>
</body>
</html>`;

  res.status(200).set("Content-Type", "text/html").send(html);
});

// ============================================================
// FCM 푸시 알림 발송 헬퍼
// ============================================================

/**
 * 특정 사용자에게 푸시 알림 발송
 */
async function sendPushToUser(
  userId: string,
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<void> {
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    const fcmToken = userDoc.data()?.fcmToken as string | undefined;
    if (!fcmToken) return;

    await admin.messaging().send({
      token: fcmToken,
      notification: { title, body },
      data: data ?? {},
      webpush: {
        notification: { icon: "/icons/Icon-192.png" },
      },
    });
  } catch (e: any) {
    // 만료된 토큰 제거
    if (e.code === "messaging/registration-token-not-registered") {
      await db.collection("users").doc(userId).update({
        fcmToken: admin.firestore.FieldValue.delete(),
      });
    }
    functions.logger.warn(`FCM 발송 실패 (user=${userId}): ${e.message}`);
  }
}

/**
 * 이벤트의 모든 티켓 소유자에게 푸시 알림 발송
 */
async function sendPushToEventUsers(
  eventId: string,
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<number> {
  const ticketsSnapshot = await db
    .collection("tickets")
    .where("eventId", "==", eventId)
    .where("status", "==", "issued")
    .get();

  const userIds = [...new Set(ticketsSnapshot.docs.map((d) => d.data().userId as string))];
  let sent = 0;

  for (const uid of userIds) {
    await sendPushToUser(uid, title, body, data);
    sent++;
  }

  return sent;
}

// ============================================================
// 1. createOrder - 주문 생성
// ============================================================
export const createOrder = functions.https.onCall(async (data: any, context) => {
  const { eventId, quantity } = data;
  const discountPolicyName: string | undefined = data?.discountPolicyName;
  const referralCode: string | undefined =
    typeof data?.referralCode === "string" && data.referralCode.trim().length > 0
      ? data.referralCode.trim()
      : undefined;
  const userId = context?.auth?.uid;
  const preferredSeatIds = Array.isArray(data?.preferredSeatIds)
    ? [...new Set(data.preferredSeatIds.filter((v: unknown) => typeof v === "string"))]
    : [];

  if (!userId) {
    throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
  }

  if (!eventId || !quantity || quantity < 1) {
    throw new functions.https.HttpsError("invalid-argument", "잘못된 요청입니다");
  }

  // 이벤트 조회
  const eventDoc = await db.collection("events").doc(eventId).get();
  if (!eventDoc.exists) {
    throw new functions.https.HttpsError("not-found", "공연을 찾을 수 없습니다");
  }

  const event = eventDoc.data()!;

  // 구매 가능 여부 확인 (0 = 무제한)
  if (event.maxTicketsPerOrder > 0 && quantity > event.maxTicketsPerOrder) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `최대 ${event.maxTicketsPerOrder}매까지 구매 가능합니다`
    );
  }

  if (quantity > event.availableSeats) {
    throw new functions.https.HttpsError("resource-exhausted", "잔여 좌석이 부족합니다");
  }

  // ── 할인 정책 검증 및 적용 ──
  let unitPrice: number = event.price;
  let appliedDiscount: string | null = null;

  if (discountPolicyName && Array.isArray(event.discountPolicies)) {
    const policy = event.discountPolicies.find(
      (p: { name: string }) => p.name === discountPolicyName
    );
    if (policy) {
      // 수량 할인: 최소 수량 충족 확인
      if (policy.type === "bulk" && quantity < policy.minQuantity) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          `이 할인은 최소 ${policy.minQuantity}매 이상 구매 시 적용됩니다`
        );
      }
      const rate = typeof policy.discountRate === "number" ? policy.discountRate : 0;
      unitPrice = Math.round(event.price * (1 - rate));
      appliedDiscount = policy.name;
    }
  } else if (!discountPolicyName && Array.isArray(event.discountPolicies)) {
    // 할인 미선택 시 수량 할인 자동 적용 (최대 할인율)
    let bestRate = 0;
    for (const p of event.discountPolicies) {
      if (p.type === "bulk" && quantity >= p.minQuantity && p.discountRate > bestRate) {
        bestRate = p.discountRate;
        appliedDiscount = p.name;
      }
    }
    if (bestRate > 0) {
      unitPrice = Math.round(event.price * (1 - bestRate));
    }
  }

  const normalizedPreferred = preferredSeatIds.slice(0, quantity);

  // 체험(데모) 사용자 여부 확인
  const userDoc = await db.collection("users").doc(userId).get();
  const isDemo = userDoc.exists && userDoc.data()?.isDemo === true;

  // 주문 생성
  const orderRef = db.collection("orders").doc();
  const order: Record<string, unknown> = {
    eventId,
    userId,
    quantity,
    unitPrice,
    totalAmount: unitPrice * quantity,
    preferredSeatIds: normalizedPreferred,
    status: "pending",
    isDemo,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(appliedDiscount ? { appliedDiscount } : {}),
    ...(referralCode ? { referralCode } : {}),
  };

  await orderRef.set(order);

  functions.logger.info(
    `주문 생성: ${orderRef.id}, 수량: ${quantity}, 단가: ${unitPrice}` +
    (appliedDiscount ? `, 할인: ${appliedDiscount}` : "")
  );

  return {
    success: true,
    orderId: orderRef.id,
    totalAmount: order.totalAmount,
  };
});

// ============================================================
// 2. confirmPaymentAndAssignSeats - 결제 확정 및 연속좌석 배정 (핵심!)
// ============================================================
export const confirmPaymentAndAssignSeats = functions.https.onCall(async (data: any, context) => {
  const { orderId } = data;
  const userId = context?.auth?.uid;

  if (!userId) {
    throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
  }

  // 트랜잭션으로 원자성 보장 (1500석 규모 성능 고려)
  const result = await db.runTransaction(async (transaction) => {
    // 주문 조회
    const orderRef = db.collection("orders").doc(orderId);
    const orderDoc = await transaction.get(orderRef);

    if (!orderDoc.exists) {
      throw new functions.https.HttpsError("not-found", "주문을 찾을 수 없습니다");
    }

    const order = orderDoc.data()!;

    if (order.userId !== userId) {
      throw new functions.https.HttpsError("permission-denied", "권한이 없습니다");
    }

    if (order.status !== "pending") {
      throw new functions.https.HttpsError("failed-precondition", "이미 처리된 주문입니다");
    }

    // Mock 결제 검증 (실제로는 PG사 검증)
    const paymentValid = true; // TODO: 실제 결제 검증 로직

    if (!paymentValid) {
      transaction.update(orderRef, { status: "failed", failReason: "결제 검증 실패" });
      return { success: false, error: "결제 검증 실패" };
    }

    // 이벤트 정보 및 수량
    const eventId = order.eventId;
    const quantity = order.quantity;
    const eventRef = db.collection("events").doc(eventId);
    const eventDoc = await transaction.get(eventRef);

    if (!eventDoc.exists) {
      throw new functions.https.HttpsError("not-found", "이벤트를 찾을 수 없습니다");
    }

    const eventData = eventDoc.data()!;

    // ═══ 스탠딩(비지정석) 모드 ═══
    if (eventData.isStanding === true) {
      const available = eventData.availableSeats || 0;
      if (available < quantity) {
        transaction.update(orderRef, {
          status: "failed",
          failReason: "잔여 수량이 부족합니다",
        });
        return { success: false, error: "잔여 수량이 부족합니다" };
      }

      // 현재 발급된 티켓 수로 entryNumber 계산
      const totalSeats = eventData.totalSeats || 0;
      const baseEntryNumber = totalSeats - available + 1;

      // 티켓 발급 (좌석 없이)
      const ticketIds: string[] = [];
      for (let i = 0; i < quantity; i++) {
        const ticketRef = db.collection("tickets").doc();
        ticketIds.push(ticketRef.id);
        transaction.set(ticketRef, {
          eventId,
          orderId,
          userId,
          seatId: "",
          seatBlockId: "",
          status: "issued",
          qrVersion: 1,
          entryNumber: baseEntryNumber + i,
          issuedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // 주문 상태 업데이트
      transaction.update(orderRef, {
        status: "paid",
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 잔여 수량 감소
      transaction.update(eventRef, {
        availableSeats: admin.firestore.FieldValue.increment(-quantity),
      });

      functions.logger.info(`스탠딩 결제 완료: 주문 ${orderId}, ${quantity}매, 입장번호 ${baseEntryNumber}~${baseEntryNumber + quantity - 1}`);

      return {
        success: true,
        seatBlockId: "",
        seatCount: quantity,
        ticketIds,
        userId,
        eventId,
      };
    }

    // ═══ 지정석 모드 (기존 로직) ═══
    // 가용 좌석 조회 (인덱스: eventId + status)
    const seatsSnapshot = await transaction.get(
      db.collection("seats")
        .where("eventId", "==", eventId)
        .where("status", "==", "available")
        .orderBy("block")
        .orderBy("floor")
        .orderBy("row")
        .orderBy("number")
    );

    const availableSeats: SeatDoc[] = seatsSnapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    })) as SeatDoc[];
    const preferredSeatIds = Array.isArray(order.preferredSeatIds)
      ? order.preferredSeatIds.filter((v: unknown) => typeof v === "string")
      : [];

    functions.logger.info(`가용 좌석 수: ${availableSeats.length}, 필요: ${quantity}`);

    // 연속좌석 탐색 알고리즘
    const consecutiveSeats = findConsecutiveSeats(availableSeats, quantity, preferredSeatIds);

    if (!consecutiveSeats) {
      transaction.update(orderRef, {
        status: "failed",
        failReason: "연속 좌석을 찾을 수 없습니다",
      });
      return { success: false, error: "연속 좌석을 찾을 수 없습니다" };
    }

    functions.logger.info(`연속좌석 찾음: ${consecutiveSeats.map((s) => s.seatKey).join(", ")}`);

    // 좌석 예약 처리
    const seatIds: string[] = [];
    for (const seat of consecutiveSeats) {
      const seatRef = db.collection("seats").doc(seat.id);
      transaction.update(seatRef, {
        status: "reserved",
        orderId: orderId,
        reservedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      seatIds.push(seat.id);
    }

    // SeatBlock 생성
    const seatBlockRef = db.collection("seatBlocks").doc();
    transaction.set(seatBlockRef, {
      eventId,
      orderId,
      userId,
      quantity,
      seatIds,
      hidden: true, // 공개 전
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 티켓 발급
    const ticketIds: string[] = [];
    for (const seatId of seatIds) {
      const ticketRef = db.collection("tickets").doc();
      ticketIds.push(ticketRef.id);
      transaction.set(ticketRef, {
        eventId,
        orderId,
        userId,
        seatId,
        seatBlockId: seatBlockRef.id,
        status: "issued",
        qrVersion: 1,
        issuedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // 주문 상태 업데이트
    transaction.update(orderRef, {
      status: "paid",
      paidAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 이벤트 잔여 좌석 감소
    transaction.update(eventRef, {
      availableSeats: admin.firestore.FieldValue.increment(-quantity),
    });

    functions.logger.info(`결제 완료 및 좌석 배정: 주문 ${orderId}, 좌석 ${seatIds.length}개`);

    return {
      success: true,
      seatBlockId: seatBlockRef.id,
      seatCount: seatIds.length,
      ticketIds,
      userId,
      eventId,
    };
  });

  // 트랜잭션 성공 시 후처리 (푸시 알림 + 마일리지 적립)
  if (result.success && result.userId) {
    const eventDoc = await db.collection("events").doc(result.eventId).get();
    const eventTitle = eventDoc.data()?.title ?? "공연";

    // 푸시 알림
    sendPushToUser(
      result.userId,
      "예매가 확정되었습니다!",
      `${eventTitle} - ${result.seatCount}매 예매 완료`,
      { type: "booking_confirmed", orderId, eventId: result.eventId },
    ).catch(() => {});

    // 마일리지 적립 (트랜잭션 외부에서 처리)
    try {
      const orderDoc = await db.collection("orders").doc(orderId).get();
      const orderData = orderDoc.data();
      if (orderData) {
        const totalAmount = Number(orderData.totalAmount ?? 0);

        // 1. 구매자 마일리지 적립 (등급별 차등: Bronze 3%, Silver 5%, Gold 7%, Platinum 10%)
        const buyerDoc = await db.collection("users").doc(result.userId).get();
        const buyerTier = buyerDoc.exists ? (buyerDoc.data()?.mileage?.tier ?? "bronze") : "bronze";
        const tierRates: Record<string, number> = {
          bronze: 0.03, silver: 0.05, gold: 0.07, platinum: 0.10,
        };
        const earnRate = tierRates[buyerTier] ?? 0.03;
        const purchaseMileage = Math.floor(totalAmount * earnRate);
        if (purchaseMileage > 0) {
          await addMileageInternal(
            result.userId,
            purchaseMileage,
            "purchase",
            `${eventTitle} 예매 적립 (${result.seatCount}매)`
          );
        }

        // 2. 추천인 마일리지 적립 (500P)
        const refCode = orderData.referralCode as string | undefined;
        if (refCode) {
          const referrerQuery = await db
            .collection("users")
            .where("referralCode", "==", refCode)
            .limit(1)
            .get();

          if (!referrerQuery.empty) {
            const referrerDoc = referrerQuery.docs[0];
            const referrerId = referrerDoc.id;

            // 자기 자신 추천 방지
            if (referrerId !== result.userId) {
              await addMileageInternal(
                referrerId,
                500,
                "referral",
                `추천 적립 (${eventTitle})`
              );
              functions.logger.info(
                `추천 마일리지 적립: referrer=${referrerId}, buyer=${result.userId}, code=${refCode}`
              );
            }
          }
        }
      }
    } catch (mileageError: any) {
      // 마일리지 적립 실패해도 결제는 성공으로 처리
      functions.logger.error(`마일리지 적립 실패: ${mileageError.message}`);
    }
  }

  return result;
});

/**
 * 연속좌석 탐색 알고리즘
 * 우선순위:
 * 1. 같은 block + floor + row에서 연속 number
 * 2. 같은 block + floor 내에서 연속 number (row 무시)
 * 3. 여러 후보 중 중앙에 가까운 좌석 우선
 */
function findConsecutiveSeats(
  seats: SeatDoc[],
  quantity: number,
  preferredSeatIds: string[] = []
): SeatDoc[] | null {
  if (seats.length < quantity) return null;
  if (quantity === 1) return [seats[0]]; // 1장은 그냥 첫 번째

  // block + floor + row 기준 그룹핑
  const groups = new Map<string, SeatDoc[]>();
  for (const seat of seats) {
    const key = `${seat.block}-${seat.floor}-${seat.row || ""}`;
    if (!groups.has(key)) {
      groups.set(key, []);
    }
    groups.get(key)!.push(seat);
  }

  // 각 그룹에서 연속 좌석 찾기
  const candidates: SeatDoc[][] = [];

  for (const [, groupSeats] of groups) {
    // number 기준 정렬
    groupSeats.sort((a, b) => a.number - b.number);

    // 연속 구간 찾기
    for (let i = 0; i <= groupSeats.length - quantity; i++) {
      let isConsecutive = true;
      for (let j = 1; j < quantity; j++) {
        if (groupSeats[i + j].number !== groupSeats[i].number + j) {
          isConsecutive = false;
          break;
        }
      }
      if (isConsecutive) {
        candidates.push(groupSeats.slice(i, i + quantity));
      }
    }
  }

  if (candidates.length === 0) {
    // row 무시하고 block + floor 기준으로 재탐색
    const blockFloorGroups = new Map<string, SeatDoc[]>();
    for (const seat of seats) {
      const key = `${seat.block}-${seat.floor}`;
      if (!blockFloorGroups.has(key)) {
        blockFloorGroups.set(key, []);
      }
      blockFloorGroups.get(key)!.push(seat);
    }

    for (const [, groupSeats] of blockFloorGroups) {
      groupSeats.sort((a, b) => a.number - b.number);

      for (let i = 0; i <= groupSeats.length - quantity; i++) {
        let isConsecutive = true;
        for (let j = 1; j < quantity; j++) {
          if (groupSeats[i + j].number !== groupSeats[i].number + j) {
            isConsecutive = false;
            break;
          }
        }
        if (isConsecutive) {
          candidates.push(groupSeats.slice(i, i + quantity));
        }
      }
    }
  }

  if (candidates.length === 0) return null;

  // ── 좌석 배정 스코어링 (seat_selection_screen.dart _scoreSequence 동일 로직) ──
  // Center(40) + Row Position(25) + Grade(15) = 최대 80점/석
  const preferredSet = new Set(preferredSeatIds);

  // 전체 row 목록 (앞열 우선 판단용)
  const allRowNums = [...new Set(seats.map((s) => {
    const r = parseInt(s.row || "1", 10);
    return isNaN(r) ? 1 : r;
  }))].sort((a, b) => a - b);

  function scoreCandidate(seq: SeatDoc[]): number {
    // 해당 row의 좌석 번호 범위 (center 계산용)
    const rowKey = `${seq[0].block}-${seq[0].floor}-${seq[0].row || ""}`;
    const rowSeats = seats.filter(
      (s) => `${s.block}-${s.floor}-${s.row || ""}` === rowKey,
    );
    const rowNumbers = rowSeats.map((s) => s.number);
    const minNum = Math.min(...rowNumbers);
    const maxNum = Math.max(...rowNumbers);
    const center = (minNum + maxNum) / 2;
    const rowWidth = maxNum - minNum;

    let totalScore = 0;
    for (const seat of seq) {
      // Center score (0-40): 가운데일수록 높음
      if (rowWidth > 0) {
        const centerOffset = Math.abs(seat.number - center) / (rowWidth / 2);
        totalScore += (1 - centerOffset) * 40;
      } else {
        totalScore += 40;
      }

      // Row position score (0-25): 30% 지점(앞쪽) 선호
      const rowNum = parseInt(seat.row || "1", 10) || 1;
      if (allRowNums.length > 1) {
        const rowIndex = allRowNums.indexOf(rowNum);
        const idealIdx = Math.min(
          Math.round(allRowNums.length * 0.3),
          allRowNums.length - 1,
        );
        const maxIdx = Math.max(1, allRowNums.length - 1);
        const rowOffset = Math.abs(rowIndex - idealIdx) / maxIdx;
        totalScore += (1 - rowOffset) * 25;
      } else {
        totalScore += 25;
      }
    }

    return totalScore / seq.length;
  }

  candidates.sort((a, b) => {
    // 선호 좌석 포함 우선
    const aPreferred = a.reduce((count, seat) => count + (preferredSet.has(seat.id) ? 1 : 0), 0);
    const bPreferred = b.reduce((count, seat) => count + (preferredSet.has(seat.id) ? 1 : 0), 0);
    if (aPreferred !== bPreferred) {
      return bPreferred - aPreferred;
    }
    // 스코어 높은 순
    return scoreCandidate(b) - scoreCandidate(a);
  });

  return candidates[0];
}

/**
 * Firestore QueryDocumentSnapshot[] → 연석 탐색 래퍼
 * findConsecutiveSeats를 재사용하여 인접 좌석을 찾고 원본 doc 참조를 반환
 */
function findAdjacentSeats(
  docs: admin.firestore.QueryDocumentSnapshot[],
  quantity: number
): admin.firestore.QueryDocumentSnapshot[] | null {
  if (quantity <= 1 && docs.length >= 1) {
    // 1매는 number 순 첫 번째
    const sorted = [...docs].sort((a, b) => (a.data().number || 0) - (b.data().number || 0));
    return [sorted[0]];
  }

  // QueryDocumentSnapshot → SeatDoc 변환
  const seatDocs: SeatDoc[] = docs.map((d) => {
    const data = d.data();
    return {
      id: d.id,
      block: data.block || "",
      floor: data.floor || "",
      row: data.row || undefined,
      number: data.number || 0,
    };
  });

  const result = findConsecutiveSeats(seatDocs, quantity);
  if (!result) return null;

  // SeatDoc → 원본 QueryDocumentSnapshot 매핑
  const resultIds = new Set(result.map((s) => s.id));
  const matched = docs.filter((d) => resultIds.has(d.id));
  // findConsecutiveSeats 결과 순서(number 순) 유지
  matched.sort((a, b) => (a.data().number || 0) - (b.data().number || 0));
  return matched.length === quantity ? matched : null;
}

// ============================================================
// 3. revealSeatsForEvent - 좌석 공개 (공연 2시간 전 정책)
// ============================================================
export const revealSeatsForEvent = functions.https.onCall(async (data: any, context) => {
  const { eventId } = data;
  await assertAdmin(context?.auth?.uid);

  if (!eventId || typeof eventId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "잘못된 요청입니다");
  }

  const batch = db.batch();
  let updateCount = 0;

  // seatBlocks hidden=false 업데이트
  const seatBlocksSnapshot = await db
    .collection("seatBlocks")
    .where("eventId", "==", eventId)
    .where("hidden", "==", true)
    .get();

  for (const doc of seatBlocksSnapshot.docs) {
    batch.update(doc.ref, { hidden: false });
    updateCount++;
  }

  await batch.commit();

  functions.logger.info(`좌석 공개: 이벤트 ${eventId}, ${updateCount}개 블록`);

  // FCM 푸시 알림: 좌석 공개 알림
  const eventDoc2 = await db.collection("events").doc(eventId).get();
  const eventTitle2 = eventDoc2.data()?.title ?? "공연";
  const sentCount = await sendPushToEventUsers(
    eventId,
    "좌석이 공개되었습니다!",
    `${eventTitle2} - 지금 바로 좌석을 확인하세요`,
    { type: "seats_revealed", eventId },
  );

  return {
    success: true,
    revealedBlocks: updateCount,
    notificationsSent: sentCount,
  };
});

// ============================================================
// 4. requestTicketCancellation - 취소/환불 처리
// ============================================================
export const requestTicketCancellation = functions.https.onCall(async (data: any, context) => {
  const { ticketId } = data;
  const userId = context?.auth?.uid;

  if (!userId) {
    throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
  }
  if (!ticketId || typeof ticketId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "잘못된 요청입니다");
  }

  return db.runTransaction(async (transaction) => {
    const ticketRef = db.collection("tickets").doc(ticketId);
    const ticketDoc = await transaction.get(ticketRef);
    if (!ticketDoc.exists) {
      throw new functions.https.HttpsError("not-found", "티켓을 찾을 수 없습니다");
    }

    const ticket = ticketDoc.data()!;
    if (ticket.userId !== userId) {
      throw new functions.https.HttpsError("permission-denied", "권한이 없습니다");
    }
    if (ticket.status !== "issued") {
      throw new functions.https.HttpsError("failed-precondition", "취소 가능한 티켓이 아닙니다");
    }
    if (ticket.entryCheckedInAt || ticket.intermissionCheckedInAt) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "입장 체크가 진행된 티켓은 취소할 수 없습니다"
      );
    }

    const eventRef = db.collection("events").doc(ticket.eventId);
    const eventDoc = await transaction.get(eventRef);
    if (!eventDoc.exists) {
      throw new functions.https.HttpsError("not-found", "공연 정보를 찾을 수 없습니다");
    }
    const event = eventDoc.data()!;
    const eventStartAt = toDate(event.startAt);
    if (!eventStartAt) {
      throw new functions.https.HttpsError("internal", "공연 시간이 올바르지 않습니다");
    }

    const now = new Date();
    const orderRef = db.collection("orders").doc(ticket.orderId);
    const orderDoc = await transaction.get(orderRef);
    if (!orderDoc.exists) {
      throw new functions.https.HttpsError("not-found", "주문 정보를 찾을 수 없습니다");
    }
    const order = orderDoc.data()!;
    const unitPrice = Number(order.unitPrice ?? 0);
    const orderCreatedAt = toDate(order.createdAt) ?? now;
    const category = event.category ?? null;

    const { refundRate, cancelFee, policy } = calculateCancelFee(
      unitPrice, orderCreatedAt, eventStartAt, category, now
    );

    if (refundRate === 0) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        policy
      );
    }

    const refundAmount = Math.round(unitPrice * refundRate);

    transaction.update(ticketRef, {
      status: "canceled",
      canceledAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (ticket.seatId) {
      const seatRef = db.collection("seats").doc(ticket.seatId);
      const seatDoc = await transaction.get(seatRef);
      if (seatDoc.exists) {
        transaction.update(seatRef, {
          status: "available",
          orderId: admin.firestore.FieldValue.delete(),
          reservedAt: admin.firestore.FieldValue.delete(),
        });
      }
    }

    transaction.update(eventRef, {
      availableSeats: admin.firestore.FieldValue.increment(1),
    });

    const orderTicketsQuery = db.collection("tickets")
      .where("orderId", "==", ticket.orderId);
    const orderTicketsSnapshot = await transaction.get(orderTicketsQuery);
    const hasRemainingIssued = orderTicketsSnapshot.docs.some((doc) => {
      if (doc.id === ticketId) return false;
      return doc.data().status === "issued";
    });

    const orderUpdates: Record<string, unknown> = {
      canceledCount: admin.firestore.FieldValue.increment(1),
      refundedAmount: admin.firestore.FieldValue.increment(refundAmount),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (!hasRemainingIssued) {
      orderUpdates.status = refundAmount > 0 ? "refunded" : "canceled";
      orderUpdates.refundedAt = admin.firestore.FieldValue.serverTimestamp();
    }
    transaction.update(orderRef, orderUpdates);

    functions.logger.info(
      `티켓 취소 완료: ticket=${ticketId}, user=${userId}, rate=${refundRate}, refund=${refundAmount}`
    );

    return {
      success: true,
      ticketId,
      refundRate,
      refundAmount,
      cancelFee,
      policy,
    };
  });
});

// ============================================================
// 5. registerScannerDevice - 스캐너 기기 등록/승인 상태 조회
// ============================================================
export const registerScannerDevice = functions.https.onCall(async (data: any, context) => {
  const { deviceId, label, platform, inviteToken } = data ?? {};

  // 초대 토큰이 있으면 로그인만 확인, 없으면 staff/admin 권한 필요
  let scannerUid: string;
  if (typeof inviteToken === "string" && inviteToken.trim().length > 0) {
    if (!context?.auth?.uid) {
      throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
    }
    scannerUid = context.auth.uid;
  } else {
    scannerUid = await assertStaffOrAdmin(context?.auth?.uid);
  }

  if (!deviceId || typeof deviceId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "기기 ID가 필요합니다");
  }

  const trimmedId = deviceId.trim();
  if (trimmedId.length < 8 || trimmedId.length > 128) {
    throw new functions.https.HttpsError("invalid-argument", "유효하지 않은 기기 ID입니다");
  }

  // 초대 토큰 검증
  let inviteApproved = false;
  if (typeof inviteToken === "string" && inviteToken.trim().length > 0) {
    const inviteRef = db.collection("scannerInvites").doc(inviteToken.trim());
    const inviteDoc = await inviteRef.get();
    if (inviteDoc.exists) {
      const inv = inviteDoc.data()!;
      const now = new Date();
      const expires = inv.expiresAt?.toDate?.() ?? new Date(0);
      if (inv.active !== false && expires > now) {
        inviteApproved = true;
        await inviteRef.update({
          usedCount: admin.firestore.FieldValue.increment(1),
          lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }
  }

  const userDoc = await db.collection("users").doc(scannerUid).get();
  const user = userDoc.data() ?? {};
  const ownerEmail = (context?.auth?.token?.email as string | undefined) ?? (user.email as string | undefined) ?? "";
  const ownerDisplayName =
    (user.displayName as string | undefined) ||
    (context?.auth?.token?.name as string | undefined) ||
    ownerEmail.split("@")[0] ||
    "scanner-user";

  const deviceRef = db.collection("scannerDevices").doc(trimmedId);
  const existingDoc = await deviceRef.get();
  const existing = existingDoc.data() ?? {};

  if (existingDoc.exists && existing.ownerUid && existing.ownerUid !== scannerUid) {
    throw new functions.https.HttpsError("permission-denied", "다른 계정에 등록된 기기입니다");
  }

  // admin 역할이거나 초대 토큰 사용 시 자동 승인
  const userRole = await getUserRole(scannerUid);
  const approved = existingDoc.exists
    ? existing.approved === true
    : (userRole === "admin" || inviteApproved);
  const blocked = existingDoc.exists ? existing.blocked === true : false;

  const payload: Record<string, unknown> = {
    ownerUid: scannerUid,
    ownerEmail,
    ownerDisplayName,
    label:
      typeof label === "string" && label.trim().length > 0 ? label.trim() : "Scanner Device",
    platform:
      typeof platform === "string" && platform.trim().length > 0 ? platform.trim() : "unknown",
    approved,
    blocked,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (!existingDoc.exists) {
    payload.requestedAt = admin.firestore.FieldValue.serverTimestamp();
  }

  await deviceRef.set(payload, { merge: true });

  return {
    success: true,
    deviceId: trimmedId,
    approved,
    blocked,
    message: blocked
      ? "차단된 기기입니다"
      : approved
          ? "승인된 기기입니다"
          : "승인 대기 중입니다",
  };
});

// ============================================================
// 5-b. createScannerInvite - 스캐너 초대링크 생성 (관리자)
// ============================================================
export const createScannerInvite = functions.https.onCall(async (data: any, context) => {
  const adminUid = await assertAdmin(context?.auth?.uid);
  const { eventId, expiresInHours } = data ?? {};

  const adminDoc = await db.collection("users").doc(adminUid).get();
  const adminEmail =
    (context?.auth?.token?.email as string | undefined) ||
    (adminDoc.data()?.email as string | undefined) ||
    "";

  const token = require("crypto").randomBytes(24).toString("hex"); // 48-char hex
  const hours = typeof expiresInHours === "number" && expiresInHours > 0 ? expiresInHours : 24;
  const expiresAt = new Date(Date.now() + hours * 60 * 60 * 1000);

  const inviteRef = db.collection("scannerInvites").doc(token);
  await inviteRef.set({
    token,
    eventId: typeof eventId === "string" && eventId.trim().length > 0 ? eventId.trim() : null,
    createdByUid: adminUid,
    createdByEmail: adminEmail,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    usedCount: 0,
    active: true,
  });

  return {
    success: true,
    token,
    expiresAt: expiresAt.toISOString(),
  };
});

// ============================================================
// 6. setScannerDeviceApproval - 스캐너 기기 승인/해제/차단 (관리자)
// ============================================================
export const setScannerDeviceApproval = functions.https.onCall(async (data: any, context) => {
  const approverUid = await assertAdmin(context?.auth?.uid);
  const { deviceId, approved, blocked } = data ?? {};

  if (!deviceId || typeof deviceId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "기기 ID가 필요합니다");
  }
  if (typeof approved !== "boolean") {
    throw new functions.https.HttpsError("invalid-argument", "approved 값이 필요합니다");
  }

  const approverDoc = await db.collection("users").doc(approverUid).get();
  const approverEmail =
    (context?.auth?.token?.email as string | undefined) ||
    (approverDoc.data()?.email as string | undefined) ||
    "";

  await db.collection("scannerDevices").doc(deviceId.trim()).set(
    {
      approved,
      blocked: blocked === true,
      approvedAt: approved ? admin.firestore.FieldValue.serverTimestamp() : admin.firestore.FieldValue.delete(),
      approvedByUid: approved ? approverUid : admin.firestore.FieldValue.delete(),
      approvedByEmail: approved ? approverEmail : admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return {
    success: true,
    deviceId: deviceId.trim(),
    approved,
    blocked: blocked === true,
  };
});

// ============================================================
// 7. issueQrToken - QR 토큰 발급 (60~120초 유효)
// ============================================================
export const issueQrToken = functions.https.onCall(async (data: any, context) => {
  const { ticketId } = data;
  const userId = context?.auth?.uid;

  if (!userId) {
    throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
  }

  // 티켓 조회
  const ticketDoc = await db.collection("tickets").doc(ticketId).get();
  if (!ticketDoc.exists) {
    throw new functions.https.HttpsError("not-found", "티켓을 찾을 수 없습니다");
  }

  const ticket = ticketDoc.data()!;

  if (ticket.userId !== userId) {
    throw new functions.https.HttpsError("permission-denied", "권한이 없습니다");
  }

  if (ticket.status !== "issued") {
    throw new functions.https.HttpsError("failed-precondition", "유효하지 않은 티켓입니다");
  }

  // JWT 토큰 생성
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    ticketId,
    eventId: ticket.eventId,
    userId,
    qrVersion: ticket.qrVersion,
    iat: now,
    exp: now + QR_TOKEN_EXPIRY,
  };

  const token = jwt.sign(payload, JWT_SECRET);

  // QR 데이터: ticketId:token 형식
  const qrData = `${ticketId}:${token}`;

  return {
    success: true,
    token: qrData,
    exp: payload.exp,
  };
});

// ============================================================
// 8. verifyAndCheckIn - 입장 검증 및 체크인(1차/2차)
// ============================================================
export const verifyAndCheckIn = functions.https.onCall(async (data: any, context) => {
  const { ticketId, qrToken } = data;
  const scannerDeviceId = (data?.scannerDeviceId as string | undefined)?.trim();
  const checkinStage = normalizeCheckinStage(data?.checkinStage);
  const scannerUid = await assertStaffOrAdmin(context?.auth?.uid);
  const actorStaffId = scannerUid;

  // 모바일 티켓(mt_) 분기 — 선언을 최상단에 배치
  const isMobileTicket = (ticketId || "").startsWith("mt_");
  const actualTicketId = isMobileTicket ? ticketId.substring(3) : ticketId;
  const collectionName = isMobileTicket ? "mobileTickets" : "tickets";

  if (!ticketId || !qrToken) {
    throw new functions.https.HttpsError("invalid-argument", "잘못된 요청입니다");
  }

  if (!scannerDeviceId) {
    await logCheckin(ticketId, actorStaffId, "notAllowedDevice", "기기 ID 누락", {
      stage: checkinStage,
    });
    return {
      success: false,
      result: "notAllowedDevice",
      title: "승인되지 않은 기기",
      message: "승인된 스캐너 기기에서만 입장 체크가 가능합니다",
    };
  }

  // 데모/어드민 테스트 디바이스는 스캐너 검증 스킵
  const isDemoDevice = scannerDeviceId === "admin-demo-device";

  if (isDemoDevice) {
    // 스캐너 디바이스 검증 건너뛰기
  } else {
  const scannerDeviceDoc = await db.collection("scannerDevices").doc(scannerDeviceId).get();
  const scannerDevice = scannerDeviceDoc.data();
  if (!scannerDeviceDoc.exists || !scannerDevice) {
    await logCheckin(ticketId, actorStaffId, "notAllowedDevice", "등록되지 않은 기기", {
      stage: checkinStage,
      scannerDeviceId,
    });
    return {
      success: false,
      result: "notAllowedDevice",
      message: "등록되지 않은 스캐너 기기입니다. 관리자 승인 후 사용해 주세요",
    };
  }
  if (scannerDevice.ownerUid !== scannerUid) {
    await logCheckin(ticketId, actorStaffId, "notAllowedDevice", "기기 소유자 불일치", {
      stage: checkinStage,
      scannerDeviceId,
    });
    return {
      success: false,
      result: "notAllowedDevice",
      message: "현재 계정으로 승인된 스캐너 기기가 아닙니다",
    };
  }
  if (scannerDevice.blocked === true || scannerDevice.approved !== true) {
    await logCheckin(ticketId, actorStaffId, "notAllowedDevice", "미승인/차단 기기", {
      stage: checkinStage,
      scannerDeviceId,
    });
    return {
      success: false,
      result: "notAllowedDevice",
      message: scannerDevice.blocked === true ? "차단된 스캐너 기기입니다" : "승인 대기 중인 스캐너 기기입니다",
    };
  }

  await db.collection("scannerDevices").doc(scannerDeviceId).set(
    {
      lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  } // end of !isDemoDevice else block

  // 토큰에서 실제 JWT 추출 (ticketId:token 형식)
  const tokenParts = qrToken.split(":");
  const actualToken = tokenParts.length > 1 ? tokenParts.slice(1).join(":") : qrToken;

  // JWT 검증
  let decoded: any;
  try {
    decoded = jwt.verify(actualToken, JWT_SECRET);
  } catch (error: any) {
    const result = error.name === "TokenExpiredError" ? "expired" : "invalidSignature";
    await logCheckin(ticketId, actorStaffId, result, error.message, {
      stage: checkinStage,
      scannerDeviceId,
    });
    return {
      success: false,
      result,
      title: result === "expired" ? "QR 만료" : "잘못된 QR",
      message: result === "expired" ? "QR이 만료되었습니다" : "잘못된 QR입니다",
    };
  }

  // 티켓 ID 일치 확인
  if (decoded.ticketId !== actualTicketId) {
    await logCheckin(actualTicketId, actorStaffId, "invalidTicket", "티켓 ID 불일치", {
      stage: checkinStage,
      scannerDeviceId,
      eventId: decoded?.eventId,
    });
    return {
      success: false,
      result: "invalidTicket",
      title: "잘못된 티켓",
      message: "잘못된 티켓입니다",
    };
  }

  // 트랜잭션으로 체크인 처리
  return db.runTransaction(async (transaction) => {
    const ticketRef = db.collection(collectionName).doc(actualTicketId);
    const ticketDoc = await transaction.get(ticketRef);

    if (!ticketDoc.exists) {
      await logCheckin(actualTicketId, actorStaffId, "invalidTicket", "티켓 없음", {
        stage: checkinStage,
        scannerDeviceId,
      });
      return {
        success: false,
        result: "invalidTicket",
        message: "티켓을 찾을 수 없습니다",
      };
    }

    const ticket = ticketDoc.data()!;
    const eventId = ticket.eventId as string;
    const normalizedStatus = normalizeMobileTicketStatus(ticket.status);
    const entryCheckedInAt = ticket.entryCheckedInAt;
    const intermissionCheckedInAt = ticket.intermissionCheckedInAt;
    const eventDoc = await transaction.get(db.collection("events").doc(eventId));
    const event = eventDoc.exists ? eventDoc.data() : null;
    const isRevealed = isEventRevealed(event);

    // QR 버전 확인 (재발급 시 이전 QR 무효화)
    if (decoded.qrVersion !== ticket.qrVersion) {
      await logCheckin(ticketId, actorStaffId, "invalidTicket", "QR 버전 불일치", {
        stage: checkinStage,
        scannerDeviceId,
        eventId,
      });
      return {
        success: false,
        result: "invalidTicket",
        title: "잘못된 티켓",
        message: "재발급된 QR입니다. 최신 QR을 사용해주세요",
      };
    }

    if (isMobileTicket && !isRevealed) {
      await logCheckin(actualTicketId, actorStaffId, "beforeReveal", "공개 전 티켓", {
        stage: checkinStage,
        scannerDeviceId,
        eventId,
      });
      return {
        success: false,
        result: "beforeReveal",
        title: "공개 전",
        message: "공연 시작 2시간 전부터 입장 QR을 사용할 수 있습니다",
        ticketStatus: "beforeReveal",
        ticketStatusLabel: "공개 전",
      };
    }

    if (normalizedStatus === "cancelled") {
      await logCheckin(actualTicketId, actorStaffId, "cancelled", "취소된 티켓", {
        stage: checkinStage,
        scannerDeviceId,
        eventId,
      });
      return {
        success: false,
        result: "cancelled",
        title: "취소됨",
        message: "취소된 티켓입니다",
        ticketStatus: "cancelled",
        ticketStatusLabel: "취소됨",
      };
    }

    if (checkinStage === "entry") {
      if (entryCheckedInAt || normalizedStatus === "used" || intermissionCheckedInAt) {
        await logCheckin(ticketId, actorStaffId, "alreadyUsed", "1차 입장 이미 완료", {
          stage: checkinStage,
          scannerDeviceId,
          eventId,
        });
        return {
          success: false,
          result: "alreadyUsed",
          title: "입장 완료",
          message: "이미 입장 완료된 티켓입니다",
          ticketStatus: "entryCheckedIn",
          ticketStatusLabel: "입장 완료",
        };
      }
    } else {
      if (!entryCheckedInAt) {
        await logCheckin(ticketId, actorStaffId, "missingEntryCheckin", "1차 입장 미완료", {
          stage: checkinStage,
          scannerDeviceId,
          eventId,
        });
        return {
          success: false,
          result: "missingEntryCheckin",
          title: "1차 입장 필요",
          message: "1차 입장 체크 후 인터미션 재입장을 처리할 수 있습니다",
        };
      }
      if (intermissionCheckedInAt || normalizedStatus === "used") {
        await logCheckin(ticketId, actorStaffId, "alreadyUsed", "2차 입장 이미 완료", {
          stage: checkinStage,
          scannerDeviceId,
          eventId,
        });
        return {
          success: false,
          result: "alreadyUsed",
          title: "사용 완료",
          message: "이미 사용 완료된 티켓입니다",
          ticketStatus: "used",
          ticketStatusLabel: "사용 완료",
        };
      }
    }

    // 좌석 정보 조회 (트랜잭션 읽기는 쓰기 전에 모두 완료해야 함)
    let seatInfo = "좌석 정보 없음";
    let seatRef: FirebaseFirestore.DocumentReference | null = null;
    let seatExists = false;
    if (isMobileTicket) {
      seatInfo = ticket.seatInfo || `${ticket.seatGrade} #${ticket.entryNumber}`;
    } else if (ticket.seatId) {
      seatRef = db.collection("seats").doc(ticket.seatId);
      const seatDoc = await transaction.get(seatRef);
      seatExists = seatDoc.exists;
      const seat = seatDoc.data();
      seatInfo = seat
        ? `${seat.block}구역 ${seat.floor} ${seat.row || ""}열 ${seat.number}번`
        : "좌석 정보 없음";
    }

    // 예매자 정보
    const buyerName = (ticket.buyerName as string) || "";
    const rawPhone = (ticket.buyerPhone as string) || "";
    const phoneLast4 = rawPhone.length >= 4 ? rawPhone.slice(-4) : "";

    // --- 여기서부터 쓰기 ---
    if (checkinStage === "entry") {
      transaction.update(ticketRef, {
        entryCheckedInAt: admin.firestore.FieldValue.serverTimestamp(),
        entryCheckinStaffId: actorStaffId,
        lastCheckInStage: "entry",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      transaction.update(ticketRef, {
        intermissionCheckedInAt: admin.firestore.FieldValue.serverTimestamp(),
        intermissionCheckinStaffId: actorStaffId,
        lastCheckInStage: "intermission",
        status: "used",
        usedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    if (seatRef && seatExists) {
      transaction.update(seatRef, { status: "used" });
    }

    const checkinRef = db.collection("checkins").doc();
    transaction.set(checkinRef, {
      eventId,
      ticketId: actualTicketId,
      staffId: actorStaffId,
      scannerDeviceId,
      stage: checkinStage,
      result: "success",
      seatInfo,
      buyerName,
      phoneLast4,
      scannedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    functions.logger.info(
      `체크인 성공: 티켓 ${ticketId}, 단계=${checkinStage}, 좌석=${seatInfo}, 예매자=${buyerName}, device=${scannerDeviceId}`
    );

    return {
      success: true,
      result: "success",
      title: checkinStage === "entry" ? "입장 완료" : "사용 완료",
      message: checkinStage === "entry"
        ? "1차 입장 처리가 완료되었습니다"
        : "인터미션 재입장 처리가 완료되었습니다",
      seatInfo,
      buyerName,
      phoneLast4,
      stage: checkinStage,
      ticketStatus: checkinStage === "entry" ? "entryCheckedIn" : "used",
      ticketStatusLabel: checkinStage === "entry" ? "입장 완료" : "사용 완료",
    };
  });
});

/**
 * 체크인 로그 기록 (실패 케이스용)
 */
async function logCheckin(
  ticketId: string,
  staffId: string,
  result: string,
  errorMessage: string,
  options: {
    eventId?: string;
    stage?: CheckinStage;
    scannerDeviceId?: string;
    seatInfo?: string;
  } = {}
): Promise<void> {
  try {
    await db.collection("checkins").add({
      eventId: options.eventId ?? "",
      ticketId,
      staffId: staffId || "unknown",
      scannerDeviceId: options.scannerDeviceId ?? "",
      stage: options.stage ?? "entry",
      result,
      seatInfo: options.seatInfo ?? null,
      errorMessage,
      scannedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    functions.logger.error("체크인 로그 기록 실패", e);
  }
}

// ============================================================
// 스케줄러: 좌석 자동 공개 (매 10분마다 체크)
// ============================================================
export const scheduledRevealSeats = functions.pubsub
  .schedule("every 10 minutes")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    // revealAt이 지났고 아직 공개 안 된 이벤트 찾기
    const eventsSnapshot = await db
      .collection("events")
      .where("revealAt", "<=", now)
      .where("status", "==", "active")
      .get();

    for (const eventDoc of eventsSnapshot.docs) {
      const eventId = eventDoc.id;

      // 해당 이벤트의 숨겨진 seatBlocks 확인
      const hiddenBlocks = await db
        .collection("seatBlocks")
        .where("eventId", "==", eventId)
        .where("hidden", "==", true)
        .limit(1)
        .get();

      if (!hiddenBlocks.empty) {
        functions.logger.info(`자동 좌석 공개 실행: ${eventId}`);

        // 좌석 공개 실행
        const batch = db.batch();
        const allHiddenBlocks = await db
          .collection("seatBlocks")
          .where("eventId", "==", eventId)
          .where("hidden", "==", true)
          .get();

        for (const doc of allHiddenBlocks.docs) {
          batch.update(doc.ref, { hidden: false });
        }

        await batch.commit();

        // FCM 푸시 알림: 자동 좌석 공개 알림
        const eventData = eventDoc.data()!;
        const title = eventData.title ?? "공연";
        sendPushToEventUsers(
          eventId,
          "좌석이 공개되었습니다!",
          `${title} - 지금 바로 좌석을 확인하세요`,
          { type: "seats_revealed", eventId },
        ).catch(() => {});
      }
    }

    return null;
  });

// ============================================================
// 소셜 로그인 - 카카오 (Custom Token 발급)
// ============================================================

/**
 * 카카오 액세스 토큰을 받아 사용자 정보 조회 후 Firebase Custom Token 발급
 * 클라이언트: 카카오 JS SDK로 로그인 → 액세스 토큰 획득 → 이 함수 호출
 */
export const signInWithKakao = functions.https.onCall(async (data, context) => {
  const accessToken = data.accessToken as string | undefined;
  if (!accessToken) {
    throw new functions.https.HttpsError("invalid-argument", "카카오 액세스 토큰이 필요합니다");
  }

  // 카카오 사용자 정보 조회
  const kakaoRes = await fetch("https://kapi.kakao.com/v2/user/me", {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  if (!kakaoRes.ok) {
    throw new functions.https.HttpsError("unauthenticated", "카카오 인증 실패");
  }

  const kakaoUser = await kakaoRes.json() as any;
  const kakaoId = String(kakaoUser.id);
  const email = kakaoUser.kakao_account?.email ?? `kakao_${kakaoId}@melonticket.app`;
  const displayName = kakaoUser.kakao_account?.profile?.nickname ?? `카카오${kakaoId.slice(-4)}`;
  const photoUrl = kakaoUser.kakao_account?.profile?.profile_image_url;

  // Firebase UID = kakao:{kakaoId}
  const uid = `kakao:${kakaoId}`;

  // Firestore 사용자 문서 생성/업데이트
  const userRef = db.collection("users").doc(uid);
  const userDoc = await userRef.get();

  if (!userDoc.exists) {
    const referralCode = await generateUniqueReferralCode();
    await userRef.set({
      email,
      displayName,
      photoUrl: photoUrl ?? null,
      provider: "kakao",
      kakaoId,
      role: "user",
      mileage: { balance: 0, tier: "bronze", totalEarned: 0 },
      referralCode,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } else {
    await userRef.update({
      lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  // Firebase Custom Token 발급
  const customToken = await admin.auth().createCustomToken(uid, {
    provider: "kakao",
    kakaoId,
  });

  return { customToken, uid, displayName, email };
});

// ============================================================
// 소셜 로그인 - 네이버 (Custom Token 발급)
// ============================================================

/**
 * 네이버 액세스 토큰을 받아 사용자 정보 조회 후 Firebase Custom Token 발급
 * 클라이언트: 네이버 로그인 SDK → 액세스 토큰 → 이 함수 호출
 */
export const signInWithNaver = functions.https.onCall(async (data, context) => {
  const accessToken = data.accessToken as string | undefined;
  if (!accessToken) {
    throw new functions.https.HttpsError("invalid-argument", "네이버 액세스 토큰이 필요합니다");
  }

  // 네이버 사용자 정보 조회
  const naverRes = await fetch("https://openapi.naver.com/v1/nid/me", {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  if (!naverRes.ok) {
    throw new functions.https.HttpsError("unauthenticated", "네이버 인증 실패");
  }

  const naverData = await naverRes.json() as any;
  if (naverData.resultcode !== "00") {
    throw new functions.https.HttpsError("unauthenticated", "네이버 사용자 정보 조회 실패");
  }

  const profile = naverData.response;
  const naverId = String(profile.id);
  const email = profile.email ?? `naver_${naverId}@melonticket.app`;
  const displayName = profile.nickname ?? profile.name ?? `네이버${naverId.slice(-4)}`;
  const photoUrl = profile.profile_image;

  // Firebase UID = naver:{naverId}
  const uid = `naver:${naverId}`;

  // Firestore 사용자 문서 생성/업데이트
  const userRef = db.collection("users").doc(uid);
  const userDoc = await userRef.get();

  if (!userDoc.exists) {
    const referralCode = await generateUniqueReferralCode();
    await userRef.set({
      email,
      displayName,
      photoUrl: photoUrl ?? null,
      provider: "naver",
      naverId,
      role: "user",
      mileage: { balance: 0, tier: "bronze", totalEarned: 0 },
      referralCode,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } else {
    await userRef.update({
      lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  // Firebase Custom Token 발급
  const customToken = await admin.auth().createCustomToken(uid, {
    provider: "naver",
    naverId,
  });

  return { customToken, uid, displayName, email };
});

/**
 * 내부용 마일리지 적립/차감 헬퍼 (Cloud Function 간 호출용)
 * addMileage callable과 동일한 로직이지만 권한 검사 없음
 */
async function addMileageInternal(
  userId: string,
  amount: number,
  type: string,
  reason: string
): Promise<void> {
  const userRef = db.collection("users").doc(userId);
  const userDoc = await userRef.get();
  if (!userDoc.exists) return;

  const userData = userDoc.data()!;
  const currentMileage = userData.mileage ?? { balance: 0, tier: "bronze", totalEarned: 0 };
  const currentBalance = currentMileage.balance ?? 0;
  const currentTotalEarned = currentMileage.totalEarned ?? 0;

  if (amount < 0 && currentBalance + amount < 0) return;

  const newBalance = currentBalance + amount;
  const newTotalEarned = amount > 0 ? currentTotalEarned + amount : currentTotalEarned;

  let newTier = "bronze";
  if (newTotalEarned >= 30000) newTier = "platinum";
  else if (newTotalEarned >= 15000) newTier = "gold";
  else if (newTotalEarned >= 5000) newTier = "silver";

  await db.collection("mileageHistory").add({
    userId,
    amount,
    type,
    reason,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await userRef.update({
    "mileage.balance": newBalance,
    "mileage.tier": newTier,
    "mileage.totalEarned": newTotalEarned,
  });

  functions.logger.info(
    `마일리지 내부 ${amount > 0 ? "적립" : "차감"}: user=${userId}, amount=${amount}, type=${type}, balance=${newBalance}`
  );
}

// ============================================================
// 9. addMileage - 마일리지 적립/차감
// ============================================================
export const addMileage = functions.https.onCall(async (data: any, context) => {
  const { userId, amount, type, reason } = data;

  // 관리자만 수동 지급 가능, 또는 서버 내부 호출 (context.auth 없으면 내부 호출 간주)
  // 일반 사용자가 직접 호출하는 것을 방지
  if (context?.auth?.uid) {
    const callerRole = await getUserRole(context.auth.uid);
    if (callerRole !== "admin") {
      // 내부 호출이 아닌 일반 사용자의 직접 호출 차단
      throw new functions.https.HttpsError("permission-denied", "관리자 권한이 필요합니다");
    }
  }

  if (!userId || typeof userId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "사용자 ID가 필요합니다");
  }
  if (typeof amount !== "number" || amount === 0) {
    throw new functions.https.HttpsError("invalid-argument", "유효한 마일리지 금액이 필요합니다");
  }
  const validTypes = ["purchase", "referral", "upgrade", "review"];
  if (!type || !validTypes.includes(type)) {
    throw new functions.https.HttpsError("invalid-argument", "유효한 마일리지 유형이 필요합니다 (purchase, referral, upgrade, review)");
  }
  if (!reason || typeof reason !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "사유가 필요합니다");
  }

  const userRef = db.collection("users").doc(userId);
  const userDoc = await userRef.get();
  if (!userDoc.exists) {
    throw new functions.https.HttpsError("not-found", "사용자를 찾을 수 없습니다");
  }

  const userData = userDoc.data()!;
  const currentMileage = userData.mileage ?? { balance: 0, tier: "bronze", totalEarned: 0 };
  const currentBalance = currentMileage.balance ?? 0;
  const currentTotalEarned = currentMileage.totalEarned ?? 0;

  // 차감 시 잔액 확인
  if (amount < 0 && currentBalance + amount < 0) {
    throw new functions.https.HttpsError("failed-precondition", "마일리지 잔액이 부족합니다");
  }

  const newBalance = currentBalance + amount;
  const newTotalEarned = amount > 0 ? currentTotalEarned + amount : currentTotalEarned;

  // 등급 계산 (totalEarned 기준)
  let newTier = "bronze";
  if (newTotalEarned >= 30000) newTier = "platinum";
  else if (newTotalEarned >= 15000) newTier = "gold";
  else if (newTotalEarned >= 5000) newTier = "silver";

  // mileageHistory 기록
  const historyRef = db.collection("mileageHistory").doc();
  await historyRef.set({
    userId,
    amount,
    type,
    reason,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // users.mileage 업데이트
  await userRef.update({
    "mileage.balance": newBalance,
    "mileage.tier": newTier,
    "mileage.totalEarned": newTotalEarned,
  });

  functions.logger.info(
    `마일리지 ${amount > 0 ? "적립" : "차감"}: user=${userId}, amount=${amount}, type=${type}, balance=${newBalance}, tier=${newTier}`
  );

  return {
    success: true,
    userId,
    amount,
    type,
    newBalance,
    newTier,
    newTotalEarned,
  };
});

// ============================================================
// 9-1. addReviewMileage - 리뷰 작성 마일리지 적립 (사용자 직접 호출)
// ============================================================
export const addReviewMileage = functions.https.onCall(async (data: any, context) => {
  const userId = context?.auth?.uid;
  if (!userId) {
    throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
  }

  const { eventId } = data;
  if (!eventId || typeof eventId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "이벤트 ID가 필요합니다");
  }

  // 리뷰 존재 확인
  const reviewSnap = await db.collection("reviews")
    .where("userId", "==", userId)
    .where("eventId", "==", eventId)
    .limit(1)
    .get();

  if (reviewSnap.empty) {
    throw new functions.https.HttpsError("failed-precondition", "리뷰를 먼저 작성해주세요");
  }

  // 이미 리뷰 마일리지 지급했는지 확인
  const existingReward = await db.collection("mileageHistory")
    .where("userId", "==", userId)
    .where("type", "==", "review")
    .where("eventId", "==", eventId)
    .limit(1)
    .get();

  if (!existingReward.empty) {
    return { success: false, reason: "이미 리뷰 마일리지가 지급되었습니다" };
  }

  // 첫 리뷰인지 확인 (전체 리뷰 수)
  const allReviews = await db.collection("reviews")
    .where("userId", "==", userId)
    .get();
  const isFirstReview = allReviews.size === 1;
  const amount = isFirstReview ? 500 : 200;

  // 마일리지 적립
  const userRef = db.collection("users").doc(userId);
  const userDoc = await userRef.get();
  if (!userDoc.exists) {
    throw new functions.https.HttpsError("not-found", "사용자를 찾을 수 없습니다");
  }

  const userData = userDoc.data()!;
  const currentMileage = userData.mileage ?? { balance: 0, tier: "bronze", totalEarned: 0 };
  const newBalance = (currentMileage.balance ?? 0) + amount;
  const newTotalEarned = (currentMileage.totalEarned ?? 0) + amount;

  let newTier = "bronze";
  if (newTotalEarned >= 30000) newTier = "platinum";
  else if (newTotalEarned >= 15000) newTier = "gold";
  else if (newTotalEarned >= 5000) newTier = "silver";

  // mileageHistory 기록
  await db.collection("mileageHistory").doc().set({
    userId,
    eventId,
    amount,
    type: "review",
    reason: isFirstReview ? "첫 리뷰 작성 보너스" : "리뷰 작성 마일리지",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // mileage 업데이트
  await userRef.update({
    "mileage.balance": newBalance,
    "mileage.tier": newTier,
    "mileage.totalEarned": newTotalEarned,
  });

  // 뱃지 부여
  const badges: string[] = userData.badges ?? [];
  const reviewCount = allReviews.size;
  const newBadges: string[] = [];

  if (reviewCount >= 1 && !badges.includes("first_review")) {
    newBadges.push("first_review");
  }
  if (reviewCount >= 3 && !badges.includes("reviewer_3")) {
    newBadges.push("reviewer_3");
  }
  if (reviewCount >= 10 && !badges.includes("reviewer_10")) {
    newBadges.push("reviewer_10");
  }

  if (newBadges.length > 0) {
    await userRef.update({
      badges: admin.firestore.FieldValue.arrayUnion(...newBadges),
    });
  }

  functions.logger.info(
    `리뷰 마일리지 적립: user=${userId}, event=${eventId}, amount=${amount}, first=${isFirstReview}, badges=${newBadges.join(",")}`
  );

  return {
    success: true,
    amount,
    isFirstReview,
    newBadges,
    newBalance,
  };
});

// ============================================================
// 10. upgradeTicketSeat - 마일리지로 좌석 등급 업그레이드
// ============================================================
export const upgradeTicketSeat = functions.https.onCall(async (data: any, context) => {
  const { ticketId } = data;
  const userId = context?.auth?.uid;

  if (!userId) {
    throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
  }
  if (!ticketId || typeof ticketId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "잘못된 요청입니다");
  }

  // 등급 순서 및 업그레이드 비용
  const gradeOrder = ["A", "S", "R", "VIP"];
  const upgradeCost: Record<string, number> = {
    "A": 2000,   // A → S
    "S": 3000,   // S → R
    "R": 5000,   // R → VIP
  };

  const result = await db.runTransaction(async (transaction) => {
    // 1. 티켓 조회
    const ticketRef = db.collection("tickets").doc(ticketId);
    const ticketDoc = await transaction.get(ticketRef);
    if (!ticketDoc.exists) {
      throw new functions.https.HttpsError("not-found", "티켓을 찾을 수 없습니다");
    }

    const ticket = ticketDoc.data()!;
    if (ticket.userId !== userId) {
      throw new functions.https.HttpsError("permission-denied", "권한이 없습니다");
    }
    if (ticket.status !== "issued") {
      throw new functions.https.HttpsError("failed-precondition", "발급된 티켓만 업그레이드 가능합니다");
    }

    // 2. 현재 좌석 조회 → 등급 확인
    const currentSeatRef = db.collection("seats").doc(ticket.seatId);
    const currentSeatDoc = await transaction.get(currentSeatRef);
    if (!currentSeatDoc.exists) {
      throw new functions.https.HttpsError("not-found", "현재 좌석 정보를 찾을 수 없습니다");
    }

    const currentSeat = currentSeatDoc.data()!;
    const currentGrade = (currentSeat.grade ?? "A") as string;
    const currentGradeIndex = gradeOrder.indexOf(currentGrade);

    if (currentGradeIndex < 0 || currentGrade === "VIP") {
      throw new functions.https.HttpsError("failed-precondition", "VIP 좌석은 더 이상 업그레이드할 수 없습니다");
    }

    const targetGrade = gradeOrder[currentGradeIndex + 1];
    const cost = upgradeCost[currentGrade];
    if (!cost) {
      throw new functions.https.HttpsError("internal", "업그레이드 비용을 확인할 수 없습니다");
    }

    // 3. 사용자 마일리지 확인
    const userRef = db.collection("users").doc(userId);
    const userDoc = await transaction.get(userRef);
    if (!userDoc.exists) {
      throw new functions.https.HttpsError("not-found", "사용자를 찾을 수 없습니다");
    }

    const userData = userDoc.data()!;
    const mileage = userData.mileage ?? { balance: 0, tier: "bronze", totalEarned: 0 };
    const balance = mileage.balance ?? 0;

    if (balance < cost) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        `마일리지가 부족합니다 (필요: ${cost}P, 보유: ${balance}P)`
      );
    }

    // 4. 상위 등급 잔여 좌석 찾기
    const availableSeatsQuery = await transaction.get(
      db.collection("seats")
        .where("eventId", "==", ticket.eventId)
        .where("grade", "==", targetGrade)
        .where("status", "==", "available")
        .limit(1)
    );

    if (availableSeatsQuery.empty) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        `${targetGrade} 등급 잔여 좌석이 없습니다`
      );
    }

    const newSeatDoc = availableSeatsQuery.docs[0];
    const newSeatRef = newSeatDoc.ref;
    const newSeat = newSeatDoc.data();

    // 5. 좌석 교환: 기존 좌석 → available, 새 좌석 → reserved
    transaction.update(currentSeatRef, {
      status: "available",
      orderId: admin.firestore.FieldValue.delete(),
      reservedAt: admin.firestore.FieldValue.delete(),
    });

    transaction.update(newSeatRef, {
      status: "reserved",
      orderId: ticket.orderId,
      reservedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 6. 티켓 seatId 업데이트
    transaction.update(ticketRef, {
      seatId: newSeatDoc.id,
      upgradedAt: admin.firestore.FieldValue.serverTimestamp(),
      previousSeatId: ticket.seatId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 7. 마일리지 차감
    const newBalance = balance - cost;
    transaction.update(userRef, {
      "mileage.balance": newBalance,
    });

    // 8. 마일리지 차감 내역 기록
    const historyRef = db.collection("mileageHistory").doc();
    transaction.set(historyRef, {
      userId,
      amount: -cost,
      type: "upgrade",
      reason: `좌석 업그레이드 (${currentGrade} → ${targetGrade})`,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const newSeatDisplay = newSeat.row
      ? `${newSeat.block}구역 ${newSeat.floor} ${newSeat.row}열 ${newSeat.number}번`
      : `${newSeat.block}구역 ${newSeat.floor} ${newSeat.number}번`;

    functions.logger.info(
      `좌석 업그레이드: ticket=${ticketId}, ${currentGrade}→${targetGrade}, cost=${cost}P, newSeat=${newSeatDoc.id}`
    );

    return {
      success: true,
      ticketId,
      previousGrade: currentGrade,
      newGrade: targetGrade,
      newSeatId: newSeatDoc.id,
      newSeatDisplay,
      cost,
      newBalance,
    };
  });

  return result;
});

// ============================================================
// 스케줄러: 공연 임박 알림 (3시간 전) + 리뷰 요청 (공연 종료 후)
// ============================================================
export const scheduledEventReminders = functions.pubsub
  .schedule("every 30 minutes")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();
    const threeHoursFromNow = new Date(now.toDate().getTime() + 3 * 60 * 60 * 1000);
    const threeAndHalfHoursFromNow = new Date(now.toDate().getTime() + 3.5 * 60 * 60 * 1000);

    // ── 공연 임박 알림 (3시간 전) ──
    const upcomingEvents = await db
      .collection("events")
      .where("startAt", ">=", admin.firestore.Timestamp.fromDate(threeHoursFromNow))
      .where("startAt", "<=", admin.firestore.Timestamp.fromDate(threeAndHalfHoursFromNow))
      .where("status", "==", "active")
      .get();

    for (const eventDoc of upcomingEvents.docs) {
      const eventData = eventDoc.data();
      if (eventData.reminderSent) continue;

      const title = eventData.title ?? "공연";
      const sent = await sendPushToEventUsers(
        eventDoc.id,
        "공연이 곧 시작됩니다!",
        `${title} - 3시간 후 공연이 시작됩니다. 준비하세요!`,
        { type: "event_reminder", eventId: eventDoc.id },
      );

      await eventDoc.ref.update({ reminderSent: true });
      functions.logger.info(`공연 임박 알림: ${eventDoc.id}, ${sent}명`);
    }

    // ── 리뷰 요청 알림 (공연 종료 2시간 후) ──
    const twoHoursAgo = new Date(now.toDate().getTime() - 2 * 60 * 60 * 1000);
    const twoAndHalfHoursAgo = new Date(now.toDate().getTime() - 2.5 * 60 * 60 * 1000);

    const endedEvents = await db
      .collection("events")
      .where("startAt", ">=", admin.firestore.Timestamp.fromDate(twoAndHalfHoursAgo))
      .where("startAt", "<=", admin.firestore.Timestamp.fromDate(twoHoursAgo))
      .where("status", "==", "active")
      .get();

    for (const eventDoc of endedEvents.docs) {
      const eventData = eventDoc.data();
      if (eventData.reviewReminderSent) continue;

      const title = eventData.title ?? "공연";
      const sent = await sendPushToEventUsers(
        eventDoc.id,
        "공연은 어떠셨나요?",
        `${title}의 후기를 남겨주세요! 다른 관객에게 큰 도움이 됩니다.`,
        { type: "review_request", eventId: eventDoc.id },
      );

      await eventDoc.ref.update({ reviewReminderSent: true });
      functions.logger.info(`리뷰 요청 알림: ${eventDoc.id}, ${sent}명`);
    }

    return null;
  });

// ============================================================
// issueGroupQrToken - 통합 QR 토큰 발급 (같은 주문 다수 티켓)
// ============================================================
export const issueGroupQrToken = functions.https.onCall(async (data: any, context) => {
  const { orderId } = data;
  const userId = context?.auth?.uid;

  if (!userId) {
    throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
  }

  if (!orderId) {
    throw new functions.https.HttpsError("invalid-argument", "주문 ID가 필요합니다");
  }

  // 해당 주문의 issued 상태 티켓 조회
  const ticketsSnap = await db.collection("tickets")
    .where("orderId", "==", orderId)
    .where("userId", "==", userId)
    .where("status", "==", "issued")
    .get();

  if (ticketsSnap.empty) {
    throw new functions.https.HttpsError("not-found", "유효한 티켓이 없습니다");
  }

  const ticketIds = ticketsSnap.docs.map(doc => doc.id);
  const firstTicket = ticketsSnap.docs[0].data();

  const now = Math.floor(Date.now() / 1000);
  const payload = {
    orderId,
    ticketIds,
    eventId: firstTicket.eventId,
    userId,
    type: "group",
    iat: now,
    exp: now + QR_TOKEN_EXPIRY,
  };

  const token = jwt.sign(payload, JWT_SECRET);
  const qrData = `group:${orderId}:${token}`;

  return {
    success: true,
    token: qrData,
    exp: payload.exp,
    ticketCount: ticketIds.length,
  };
});

// ============================================================
// verifyAndCheckInGroup - 통합 QR 일괄 체크인
// ============================================================
export const verifyAndCheckInGroup = functions.https.onCall(async (data: any, context) => {
  const { orderId, qrToken } = data;
  const scannerDeviceId = (data?.scannerDeviceId as string | undefined)?.trim();
  const checkinStage = normalizeCheckinStage(data?.checkinStage);
  const scannerUid = await assertStaffOrAdmin(context?.auth?.uid);

  if (!orderId || !qrToken) {
    throw new functions.https.HttpsError("invalid-argument", "잘못된 요청입니다");
  }

  if (!scannerDeviceId) {
    return { success: false, result: "notAllowedDevice", message: "기기 ID 누락" };
  }

  // 스캐너 디바이스 검증 (데모 디바이스는 스킵)
  const isDemoDevice = scannerDeviceId === "admin-demo-device";
  if (!isDemoDevice) {
    const devDoc = await db.collection("scannerDevices").doc(scannerDeviceId).get();
    const dev = devDoc.data();
    if (!devDoc.exists || !dev) {
      return { success: false, result: "notAllowedDevice", message: "등록되지 않은 스캐너 기기입니다" };
    }
    if (dev.ownerUid !== scannerUid) {
      return { success: false, result: "notAllowedDevice", message: "현재 계정으로 승인된 기기가 아닙니다" };
    }
    if (dev.blocked === true || dev.approved !== true) {
      return { success: false, result: "notAllowedDevice", message: dev.blocked ? "차단된 기기입니다" : "승인 대기 중입니다" };
    }
  }

  // JWT 검증
  let decoded: any;
  try {
    decoded = jwt.verify(qrToken, JWT_SECRET);
  } catch (error: any) {
    const result = error.name === "TokenExpiredError" ? "expired" : "invalidSignature";
    return { success: false, result, message: result === "expired" ? "QR이 만료되었습니다" : "잘못된 QR입니다" };
  }

  if (decoded.orderId !== orderId || decoded.type !== "group") {
    return { success: false, result: "invalidTicket", message: "잘못된 통합 QR입니다" };
  }

  const ticketIds: string[] = decoded.ticketIds || [];
  if (ticketIds.length === 0) {
    return { success: false, result: "invalidTicket", message: "티켓 정보가 없습니다" };
  }

  // 트랜잭션으로 일괄 체크인
  return db.runTransaction(async (transaction) => {
    const ticketRefs = ticketIds.map(id => db.collection("tickets").doc(id));
    const ticketDocs = await Promise.all(ticketRefs.map(ref => transaction.get(ref)));

    let checkedCount = 0;
    let alreadyCheckedCount = 0;
    const seatInfoList: string[] = [];

    for (let i = 0; i < ticketDocs.length; i++) {
      const doc = ticketDocs[i];
      if (!doc.exists) continue;
      const t = doc.data()!;

      if (t.status === "canceled") continue;

      // 좌석 정보 조회
      let seatInfo = "좌석 정보 없음";
      if (t.seatId) {
        const seatDoc = await transaction.get(db.collection("seats").doc(t.seatId));
        const seat = seatDoc.data();
        if (seat) {
          seatInfo = `${seat.grade || ""}${seat.grade ? " " : ""}${seat.block}구역 ${seat.row || ""}${seat.row ? "열 " : ""}${seat.number}번`;
        }
      } else if (t.entryNumber) {
        seatInfo = `스탠딩 ${t.entryNumber}번`;
      }

      if (checkinStage === "entry") {
        if (t.entryCheckedInAt || t.status === "used") {
          alreadyCheckedCount++;
          seatInfoList.push(`${seatInfo} (입장완료)`);
          continue;
        }
        transaction.update(ticketRefs[i], {
          entryCheckedInAt: admin.firestore.FieldValue.serverTimestamp(),
          entryCheckinStaffId: scannerUid,
          lastCheckInStage: "entry",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        if (!t.entryCheckedInAt) {
          seatInfoList.push(`${seatInfo} (1차 미입장)`);
          continue;
        }
        if (t.intermissionCheckedInAt || t.status === "used") {
          alreadyCheckedCount++;
          seatInfoList.push(`${seatInfo} (재입장완료)`);
          continue;
        }
        transaction.update(ticketRefs[i], {
          intermissionCheckedInAt: admin.firestore.FieldValue.serverTimestamp(),
          intermissionCheckinStaffId: scannerUid,
          lastCheckInStage: "intermission",
          status: "used",
          usedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      seatInfoList.push(seatInfo);
      checkedCount++;

      // 체크인 로그
      const checkinRef = db.collection("checkins").doc();
      transaction.set(checkinRef, {
        eventId: decoded.eventId,
        ticketId: ticketIds[i],
        staffId: scannerUid,
        scannerDeviceId,
        stage: checkinStage,
        result: "success",
        seatInfo,
        scannedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    if (checkedCount === 0 && alreadyCheckedCount > 0) {
      return {
        success: false,
        result: "alreadyUsed",
        message: `전체 ${ticketIds.length}매 이미 입장 완료`,
        seatInfo: seatInfoList.join("\n"),
      };
    }

    const title = checkinStage === "entry" ? "단체 입장 확인" : "단체 재입장 확인";
    const msg = alreadyCheckedCount > 0
      ? `${ticketIds.length}명 중 ${checkedCount}명 추가 입장`
      : `총 ${checkedCount}명 입장 완료`;

    return {
      success: true,
      result: "success",
      title,
      message: msg,
      seatInfo: seatInfoList.join("\n"),
      stage: checkinStage,
      checkedCount,
      totalCount: ticketIds.length,
    };
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// AI 좌석 자동 인식 — Claude Vision으로 배치도 이미지 분석
// ═══════════════════════════════════════════════════════════════════════════

export const analyzeSeatLayout = functions
  .runWith({ timeoutSeconds: 120, memory: "512MB" })
  .https.onCall(async (data: any, context) => {
    await assertAdmin(context?.auth?.uid);

    const { imageUrl, gridCols, gridRows, stagePosition } = data;
    if (!imageUrl || !gridCols || !gridRows) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "imageUrl, gridCols, gridRows가 필요합니다"
      );
    }

    // 환경 변수에서 API 키 가져오기 (.env.local 또는 Secret Manager)
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "ANTHROPIC_API_KEY 환경변수가 설정되지 않았습니다. functions/.env 파일에 추가해주세요."
      );
    }

    const anthropic = new Anthropic({ apiKey });

    // 이미지 다운로드
    let imageBase64: string;
    let mediaType: "image/jpeg" | "image/png" | "image/gif" | "image/webp";
    try {
      const response = await fetch(imageUrl);
      const buffer = await response.arrayBuffer();
      imageBase64 = Buffer.from(buffer).toString("base64");
      const ct = response.headers.get("content-type") || "image/jpeg";
      if (ct.includes("png")) mediaType = "image/png";
      else if (ct.includes("webp")) mediaType = "image/webp";
      else if (ct.includes("gif")) mediaType = "image/gif";
      else mediaType = "image/jpeg";
    } catch (e) {
      throw new functions.https.HttpsError("internal", `이미지 다운로드 실패: ${e}`);
    }

    const stagePos = stagePosition || "top";
    const prompt = `이 이미지는 공연장 좌석배치도입니다.
이 배치도를 ${gridCols}x${gridRows} 그리드에 매핑해주세요.
무대 위치: ${stagePos === "top" ? "상단" : "하단"}

각 좌석의 위치를 분석하여 다음 JSON 형식으로 반환해주세요:

{
  "seats": [
    {"x": 0, "y": 0, "zone": "A", "floor": "1층", "row": "1", "number": 1, "grade": "VIP"},
    ...
  ],
  "labels": [
    {"x": 0, "y": 0, "text": "A구역", "type": "section"},
    ...
  ],
  "stageWidthRatio": 0.4,
  "stageHeight": 28
}

규칙:
1. x는 0~${gridCols - 1}, y는 0~${gridRows - 1} 범위
2. 무대는 ${stagePos === "top" ? "상단(y=0 근처)" : "하단(y=${gridRows - 1} 근처)"}에 위치
3. 좌석 구역(zone)은 이미지에 표시된 구역명을 사용 (A, B, C, D 등)
4. 등급(grade)은 좌석 위치 기반으로 추정: 무대 가까운 정면=VIP, 정면 중간=R, 측면/후면=S, 2층/맨뒤=A
5. 열(row)과 번호(number)는 구역 내에서 순서대로 배정
6. 구역 라벨도 적절한 위치에 추가
7. 좌석 간 간격을 1셀 유지하여 도트맵처럼 보이게
8. 실제 좌석이 있는 위치만 포함 (빈 공간은 비워두기)
9. 이미지에서 보이는 좌석 배치 패턴을 최대한 정확하게 반영

JSON만 반환하고 다른 텍스트는 포함하지 마세요.`;

    try {
      const response = await anthropic.messages.create({
        model: "claude-sonnet-4-20250514",
        max_tokens: 16000,
        messages: [
          {
            role: "user",
            content: [
              {
                type: "image",
                source: {
                  type: "base64",
                  media_type: mediaType,
                  data: imageBase64,
                },
              },
              { type: "text", text: prompt },
            ],
          },
        ],
      });

      // 응답에서 JSON 추출
      const textBlock = response.content.find((b) => b.type === "text");
      if (!textBlock || textBlock.type !== "text") {
        throw new functions.https.HttpsError("internal", "AI 응답에 텍스트가 없습니다");
      }

      let jsonStr = textBlock.text.trim();
      // 코드블록 래핑 제거
      if (jsonStr.startsWith("```")) {
        jsonStr = jsonStr.replace(/^```(?:json)?\n?/, "").replace(/\n?```$/, "");
      }

      const parsed = JSON.parse(jsonStr);
      return {
        success: true,
        seats: parsed.seats || [],
        labels: parsed.labels || [],
        stageWidthRatio: parsed.stageWidthRatio,
        stageHeight: parsed.stageHeight,
        totalSeats: (parsed.seats || []).length,
      };
    } catch (e: any) {
      if (e.code) throw e; // HttpsError는 그대로
      throw new functions.https.HttpsError("internal", `AI 분석 실패: ${e.message}`);
    }
  });

// ============================================================
// 네이버 티켓 파이프라인
// ============================================================

import { v4 as uuidv4 } from "uuid";

type NaverTicketLink = {
  ticketId: string;
  accessToken: string;
  entryNumber: number;
  url: string;
};

const MOBILE_TICKET_PUBLIC_URL = "https://melonticket-web-20260216.vercel.app/m/";

function getOptionalBotApiKey(): string | null {
  return functions.config().bot?.apikey || process.env.BOT_API_KEY || null;
}

function getRequiredBotApiKey(): string {
  const apiKey = getOptionalBotApiKey();
  if (!apiKey) {
    throw new Error("BOT_API_KEY 환경변수가 설정되지 않았습니다");
  }
  return apiKey;
}

function getBearerToken(authHeader: string | string[] | undefined): string {
  const header = Array.isArray(authHeader) ? authHeader[0] : authHeader || "";
  return header.replace(/^Bearer\s+/i, "").trim();
}

function requireBotRequestAuth(req: any, res: any): boolean {
  let apiKey: string;
  try {
    apiKey = getRequiredBotApiKey();
  } catch (error: any) {
    res.status(500).json({ error: error?.message || "BOT_API_KEY 환경변수가 설정되지 않았습니다" });
    return false;
  }

  if (getBearerToken(req.headers.authorization) !== apiKey) {
    res.status(401).json({ error: "Unauthorized" });
    return false;
  }

  return true;
}

function httpStatusFromFunctionsErrorCode(code: string): number {
  switch (code) {
  case "invalid-argument":
    return 400;
  case "unauthenticated":
    return 401;
  case "permission-denied":
    return 403;
  case "not-found":
    return 404;
  case "already-exists":
    return 409;
  case "failed-precondition":
    return 412;
  case "resource-exhausted":
    return 422;
  default:
    return 500;
  }
}

function sendHttpError(res: any, error: any, logLabel: string): void {
  const code = typeof error?.code === "string" ? error.code.replace(/^functions\//, "") : null;
  if (code) {
    res.status(httpStatusFromFunctionsErrorCode(code)).json({
      error: error?.message || "Request failed",
      code,
    });
    return;
  }

  functions.logger.error(logLabel, error);
  res.status(500).json({ error: error?.message || "Internal server error" });
}

async function enqueueNaverOrderSmsTask(params: {
  eventId: string;
  orderId: string;
  buyerName: string;
  buyerPhone: string;
  productName: string;
  seatGrade: string;
  quantity: number;
  ticketUrls: NaverTicketLink[];
  dryRun: boolean;
  skipSms?: boolean;
  logPrefix?: string;
}): Promise<void> {
  if (params.dryRun || params.skipSms) {
    return;
  }

  const now = admin.firestore.Timestamp.now();
  const baseFields = {
    eventId: params.eventId,
    naverOrderId: params.orderId,
    buyerName: params.buyerName,
    buyerPhone: params.buyerPhone,
    sentAt: null,
    error: null,
  };

  try {
    // 주문 확인 문자는 oprncllclcl 봇이 뿌리오로 직접 발송
    // 여기서는 모바일 티켓 링크 문자만 큐잉
    await db.collection("smsTasks").add({
      ...baseFields,
      type: "mobileTicket",
      productName: params.productName,
      seatGrade: params.seatGrade,
      quantity: params.quantity,
      ticketUrls: params.ticketUrls.map((ticket) => ticket.url),
      status: "pending",
      priority: 1,
      createdAt: now,
    });
  } catch (smsErr: any) {
    functions.logger.warn(
      `${params.logPrefix || ""}SMS 태스크 생성 실패 (주문은 정상 생성됨):`,
      smsErr.message,
    );
  }
}

async function createNaverOrderInternal(
  raw: any,
  options: { logPrefix?: string } = {},
): Promise<{ success: true; dryRun: boolean; orderId: string; tickets: NaverTicketLink[] }> {
  let input: ParsedNaverOrderCreateInput;
  try {
    input = parseNaverOrderCreateInput(raw);
  } catch (error) {
    if (error instanceof NaverTicketLogicError) {
      throw new functions.https.HttpsError(error.code as functions.https.FunctionsErrorCode, error.message);
    }
    throw error;
  }

  const dupSnap = await db.collection("naverOrders")
    .where("naverOrderId", "==", input.naverOrderId)
    .where("eventId", "==", input.eventId)
    .limit(1)
    .get();
  if (!dupSnap.empty) {
    throw new functions.https.HttpsError("already-exists", "이미 등록된 네이버 주문번호입니다");
  }

  const eventDoc = await db.collection("events").doc(input.eventId).get();
  if (!eventDoc.exists) {
    throw new functions.https.HttpsError("not-found", "이벤트를 찾을 수 없습니다");
  }
  const eventData = eventDoc.data()!;
  const seatAssignMode = eventData.seatAssignMode || "immediate";
  const isDeferred = seatAssignMode === "deferred";

  const now = admin.firestore.Timestamp.now();
  const ticketIds: string[] = [];
  const ticketUrls: NaverTicketLink[] = [];
  const batch = db.batch();

  if (isDeferred) {
    // ── deferred 모드: 좌석 미배정, 티켓만 생성 ──
    const activeTicketsSnap = await db.collection("mobileTickets")
      .where("eventId", "==", input.eventId)
      .where("seatGrade", "==", input.seatGrade)
      .where("status", "==", "active")
      .get();
    const nextEntryNumber = activeTicketsSnap.size + 1;

    for (let i = 0; i < input.quantity; i++) {
      const ticketRef = db.collection("mobileTickets").doc();
      const accessToken = uuidv4();
      const entryNumber = nextEntryNumber + i;

      batch.set(ticketRef, {
        naverOrderId: "",
        eventId: input.eventId,
        seatGrade: input.seatGrade,
        seatId: null,
        seatNumber: null,
        seatInfo: "좌석 미확정",
        buyerName: input.buyerName,
        buyerPhone: input.buyerPhone,
        status: "active",
        issuedAt: now,
        usedAt: null,
        cancelledAt: null,
        qrVersion: 1,
        accessToken,
        entryNumber,
        orderIndex: i + 1,
        totalInOrder: input.quantity,
        entryCheckedInAt: null,
        lastCheckInStage: null,
      });

      ticketIds.push(ticketRef.id);
      ticketUrls.push({
        ticketId: ticketRef.id,
        accessToken,
        entryNumber,
        url: `${MOBILE_TICKET_PUBLIC_URL}${accessToken}`,
      });
    }
  } else {
    // ── immediate 모드: 기존처럼 즉시 좌석 배정 ──
    const allSeatsSnap = await db.collection("seats")
      .where("eventId", "==", input.eventId)
      .where("grade", "==", input.seatGrade)
      .where("status", "==", "available")
      .get();

    if (allSeatsSnap.size < input.quantity) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        `${input.seatGrade} 등급 잔여 좌석이 부족합니다 (잔여: ${allSeatsSnap.size}, 요청: ${input.quantity})`,
      );
    }

    const selectedSeatDocs = findAdjacentSeats(allSeatsSnap.docs, input.quantity);
    if (!selectedSeatDocs) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        `${input.seatGrade} 등급에 연석 ${input.quantity}매를 찾을 수 없습니다 (잔여 ${allSeatsSnap.size}석이지만 인접 좌석 부족)`,
      );
    }

    const activeTicketsSnap = await db.collection("mobileTickets")
      .where("eventId", "==", input.eventId)
      .where("seatGrade", "==", input.seatGrade)
      .where("status", "==", "active")
      .get();
    const nextEntryNumber = activeTicketsSnap.size + 1;

    selectedSeatDocs.forEach((seatDoc, index) => {
      const seat = seatDoc.data();
      const ticketRef = db.collection("mobileTickets").doc();
      const accessToken = uuidv4();
      const entryNumber = nextEntryNumber + index;
      const seatInfo = [seat.floor, seat.block, seat.row ? `${seat.row}열` : null, `${seat.number}번`]
        .filter(Boolean)
        .join(" ");

      batch.set(ticketRef, {
        naverOrderId: "",
        eventId: input.eventId,
        seatGrade: input.seatGrade,
        seatId: seatDoc.id,
        seatNumber: `${seat.number}`,
        seatInfo,
        buyerName: input.buyerName,
        buyerPhone: input.buyerPhone,
        status: "active",
        issuedAt: now,
        usedAt: null,
        cancelledAt: null,
        qrVersion: 1,
        accessToken,
        entryNumber,
        orderIndex: index + 1,
        totalInOrder: input.quantity,
        entryCheckedInAt: null,
        lastCheckInStage: null,
      });

      batch.update(seatDoc.ref, {
        status: "reserved",
        updatedAt: now,
      });

      ticketIds.push(ticketRef.id);
      ticketUrls.push({
        ticketId: ticketRef.id,
        accessToken,
        entryNumber,
        url: `${MOBILE_TICKET_PUBLIC_URL}${accessToken}`,
      });
    });
  }

  const orderRef = db.collection("naverOrders").doc();
  batch.set(orderRef, {
    naverOrderId: input.naverOrderId,
    buyerName: input.buyerName,
    buyerPhone: input.buyerPhone,
    productName: input.productName,
    quantity: input.quantity,
    orderDate: input.orderDate ? admin.firestore.Timestamp.fromDate(new Date(input.orderDate)) : now,
    status: "confirmed",
    ticketIds,
    eventId: input.eventId,
    seatGrade: input.seatGrade,
    createdAt: now,
    cancelledAt: null,
    cancelReason: null,
    memo: input.memo,
  });

  ticketIds.forEach((ticketId) => {
    batch.update(db.collection("mobileTickets").doc(ticketId), {
      naverOrderId: orderRef.id,
    });
  });

  await batch.commit();

  await enqueueNaverOrderSmsTask({
    eventId: input.eventId,
    orderId: orderRef.id,
    buyerName: input.buyerName,
    buyerPhone: input.buyerPhone,
    productName: input.productName || eventData?.title || "",
    seatGrade: input.seatGrade,
    quantity: input.quantity,
    ticketUrls,
    dryRun: input.dryRun,
    skipSms: input.skipSms,
    logPrefix: options.logPrefix,
  });

  functions.logger.info(
    `${options.logPrefix || ""}네이버 주문 생성${input.dryRun ? " (테스트)" : ""}: ${input.naverOrderId}, ${input.buyerName}, ${input.seatGrade} x${input.quantity}, 티켓 ${ticketIds.length}장`,
  );

  return {
    success: true,
    dryRun: input.dryRun,
    orderId: orderRef.id,
    tickets: ticketUrls,
  };
}

// ============================================================
// assignDeferredSeats - 미확정 티켓에 좌석 일괄 배정 (놀티켓 연동)
// ============================================================
// 미판매 엑셀 업로드 후 available 좌석이 세팅된 상태에서 호출.
// eventId + seatGrade 기준으로 seatId가 null인 active 티켓을 찾아 연석 우선 배정.
export const assignDeferredSeats = functions.https.onCall(async (data: any, context) => {
  await assertAdmin(context?.auth?.uid);

  const eventId = (data.eventId || "").trim();
  const seatGrade = (data.seatGrade || "").trim();
  if (!eventId || !seatGrade) {
    throw new functions.https.HttpsError("invalid-argument", "eventId와 seatGrade가 필요합니다");
  }

  // 미확정(seatId == null) 티켓 조회
  const unassignedSnap = await db.collection("mobileTickets")
    .where("eventId", "==", eventId)
    .where("seatGrade", "==", seatGrade)
    .where("status", "==", "active")
    .where("seatId", "==", null)
    .get();

  if (unassignedSnap.empty) {
    return { success: true, assigned: 0, message: "배정할 미확정 티켓이 없습니다" };
  }

  // available 좌석 조회
  const availableSnap = await db.collection("seats")
    .where("eventId", "==", eventId)
    .where("grade", "==", seatGrade)
    .where("status", "==", "available")
    .get();

  if (availableSnap.size < unassignedSnap.size) {
    throw new functions.https.HttpsError(
      "resource-exhausted",
      `잔여 좌석 부족 (미확정 ${unassignedSnap.size}매, 잔여 ${availableSnap.size}석)`,
    );
  }

  // 연석 우선으로 좌석 배정
  const selectedSeats = findAdjacentSeats(availableSnap.docs, unassignedSnap.size);
  if (!selectedSeats) {
    throw new functions.https.HttpsError(
      "resource-exhausted",
      `연석 ${unassignedSnap.size}매를 찾을 수 없습니다 (잔여 ${availableSnap.size}석)`,
    );
  }

  const now = admin.firestore.Timestamp.now();
  const batch = db.batch();
  const assignments: Array<{ ticketId: string; seatInfo: string }> = [];

  unassignedSnap.docs.forEach((ticketDoc, index) => {
    const seatDoc = selectedSeats[index];
    const seat = seatDoc.data();
    const seatInfo = [seat.floor, seat.block, seat.row ? `${seat.row}열` : null, `${seat.number}번`]
      .filter(Boolean)
      .join(" ");

    batch.update(ticketDoc.ref, {
      seatId: seatDoc.id,
      seatNumber: `${seat.number}`,
      seatInfo,
      updatedAt: now,
    });

    batch.update(seatDoc.ref, {
      status: "reserved",
      updatedAt: now,
    });

    assignments.push({ ticketId: ticketDoc.id, seatInfo });
  });

  await batch.commit();

  functions.logger.info(
    `좌석 사후 배정 완료: ${eventId}, ${seatGrade} x${assignments.length}매`,
  );

  return {
    success: true,
    assigned: assignments.length,
    assignments,
  };
});

async function getNaverOrderDocById(orderId: string) {
  const orderRef = db.collection("naverOrders").doc(orderId);
  const orderDoc = await orderRef.get();
  if (!orderDoc.exists) {
    throw new functions.https.HttpsError("not-found", "주문을 찾을 수 없습니다");
  }
  return orderDoc;
}

async function getNaverOrderDocByNaverOrderId(naverOrderId: string) {
  const snap = await db.collection("naverOrders")
    .where("naverOrderId", "==", naverOrderId)
    .limit(1)
    .get();

  if (snap.empty) {
    throw new functions.https.HttpsError("not-found", "해당 네이버 주문을 찾을 수 없습니다");
  }

  return snap.docs[0];
}

async function cancelNaverOrderInternal(
  orderDoc: admin.firestore.DocumentSnapshot | admin.firestore.QueryDocumentSnapshot,
  options: { allowAlreadyCancelled?: boolean; logPrefix?: string } = {},
): Promise<{
  success: true;
  cancelledTickets: number;
  orderId: string;
  alreadyCancelled?: boolean;
  message?: string;
}> {
  const order = orderDoc.data();
  if (!order) {
    throw new functions.https.HttpsError("not-found", "주문을 찾을 수 없습니다");
  }

  try {
    const policy = evaluateCancelOrderStatus(order.status, options.allowAlreadyCancelled === true);
    if (policy.alreadyCancelled) {
      return {
        success: true,
        cancelledTickets: 0,
        orderId: orderDoc.id,
        alreadyCancelled: true,
        message: policy.message,
      };
    }
  } catch (error) {
    if (error instanceof NaverTicketLogicError) {
      throw new functions.https.HttpsError(error.code as functions.https.FunctionsErrorCode, error.message);
    }
    throw error;
  }

  const now = admin.firestore.Timestamp.now();
  const batch = db.batch();
  const ticketIds: string[] = order.ticketIds || [];

  for (const ticketId of ticketIds) {
    const ticketRef = db.collection("mobileTickets").doc(ticketId);
    const ticketDoc = await ticketRef.get();
    if (!ticketDoc.exists) continue;

    const ticket = ticketDoc.data()!;
    batch.update(ticketRef, {
      status: "cancelled",
      cancelledAt: now,
    });

    if (ticket.seatId) {
      batch.update(db.collection("seats").doc(ticket.seatId), {
        status: "available",
        updatedAt: now,
      });
    }
  }

  batch.update(orderDoc.ref, {
    status: "cancelled",
    cancelledAt: now,
  });

  await batch.commit();

  functions.logger.info(
    `${options.logPrefix || ""}네이버 주문 취소: ${orderDoc.id}, 티켓 ${ticketIds.length}장 취소`,
  );

  return {
    success: true,
    cancelledTickets: ticketIds.length,
    orderId: orderDoc.id,
  };
}

/**
 * 네이버 주문 생성 + 등급별 선착순 좌석 배정 + 모바일 티켓 발급
 */
export const createNaverOrder = functions.https.onCall(async (data: any, context) => {
  await assertAdmin(context?.auth?.uid);
  return createNaverOrderInternal(data);
});

/**
 * 네이버 주문 취소 + 좌석 해제 + 번호 땡김
 */
export const cancelNaverOrder = functions.https.onCall(async (data: any, context) => {
  await assertAdmin(context?.auth?.uid);

  const { orderId } = data;
  if (!orderId) {
    throw new functions.https.HttpsError("invalid-argument", "orderId가 필요합니다");
  }

  const orderDoc = await getNaverOrderDocById(orderId);
  return cancelNaverOrderInternal(orderDoc);
});

/**
 * 로그인한 사용자 계정에 네이버 주문 연결
 */
export const claimNaverOrder = functions.https.onCall(async (data: any, context) => {
  const userId = context?.auth?.uid;
  if (!userId) {
    throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
  }

  const naverOrderId = typeof data?.naverOrderId === "string" ? data.naverOrderId.trim() : "";
  const buyerPhoneInput = typeof data?.buyerPhone === "string" ? data.buyerPhone : "";
  const buyerPhoneDigits = buyerPhoneInput.replace(/\D/g, "");

  if (!naverOrderId || buyerPhoneDigits.length < 4) {
    throw new functions.https.HttpsError("invalid-argument", "주문번호와 연락처 확인 정보가 필요합니다");
  }

  const orderDoc = await getNaverOrderDocByNaverOrderId(naverOrderId);
  const order = orderDoc.data();
  if (!order) {
    throw new functions.https.HttpsError("not-found", "주문을 찾을 수 없습니다");
  }

  const orderBuyerPhoneDigits = String(order.buyerPhone || "").replace(/\D/g, "");
  const phoneMatches =
    buyerPhoneDigits.length >= 7
      ? orderBuyerPhoneDigits === buyerPhoneDigits
      : orderBuyerPhoneDigits.endsWith(buyerPhoneDigits);

  if (!phoneMatches) {
    throw new functions.https.HttpsError("permission-denied", "주문 정보가 일치하지 않습니다");
  }

  if (order.userId && order.userId !== userId) {
    throw new functions.https.HttpsError("already-exists", "다른 계정에 이미 연결된 주문입니다");
  }

  if (order.userId === userId) {
    return {
      success: true,
      alreadyLinked: true,
      orderId: orderDoc.id,
      eventId: order.eventId,
    };
  }

  await orderDoc.ref.set({
    userId,
    linkedAt: admin.firestore.FieldValue.serverTimestamp(),
    linkSource: "selfClaim",
  }, { merge: true });

  return {
    success: true,
    alreadyLinked: false,
    orderId: orderDoc.id,
    eventId: order.eventId,
  };
});

/**
 * 모바일 티켓 QR 토큰 발급 (비로그인 — accessToken 검증)
 */
export const issueMobileQrToken = functions.https.onCall(async (data: any) => {
  const { ticketId, accessToken } = data;
  if (!ticketId || !accessToken) {
    throw new functions.https.HttpsError("invalid-argument", "ticketId와 accessToken이 필요합니다");
  }

  const ticketDoc = await db.collection("mobileTickets").doc(ticketId).get();
  if (!ticketDoc.exists) {
    throw new functions.https.HttpsError("not-found", "티켓을 찾을 수 없습니다");
  }

  const ticket = ticketDoc.data()!;
  if (ticket.accessToken !== accessToken) {
    throw new functions.https.HttpsError("permission-denied", "잘못된 접근입니다");
  }

  const ticketStatus = normalizeMobileTicketStatus(ticket.status);
  if (ticketStatus === "cancelled") {
    throw new functions.https.HttpsError("failed-precondition", "취소된 티켓입니다");
  }
  if (ticketStatus === "used") {
    throw new functions.https.HttpsError("failed-precondition", "이미 사용 완료된 티켓입니다");
  }

  // 이벤트 조회 병렬화 (티켓 검증 후)
  const eventDoc = await db.collection("events").doc(ticket.eventId).get();
  const event = eventDoc.exists ? eventDoc.data() : null;
  if (!isEventRevealed(event)) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "공연 시작 2시간 전부터 입장 QR을 발급할 수 있습니다",
    );
  }

  const token = jwt.sign(
    {
      ticketId,
      eventId: ticket.eventId,
      qrVersion: ticket.qrVersion || 1,
      type: "mobile",
      seatGrade: ticket.seatGrade || null,
      seatInfo: ticket.seatInfo || null,
      entryNumber: ticket.entryNumber || null,
    },
    JWT_SECRET,
    { expiresIn: QR_TOKEN_EXPIRY }
  );

  // QR 데이터: mt_{ticketId}:{jwt} 형식 (스캐너가 mt_ 접두어로 모바일 티켓 구분)
  const qrData = `mt_${ticketId}:${token}`;

  return {
    success: true,
    token: qrData,
    exp: Math.floor(Date.now() / 1000) + QR_TOKEN_EXPIRY,
  };
});

/**
 * OG 메타데이터 조회 (카카오톡/SNS 미리보기용)
 * GET /getTicketOgMeta?token=ACCESS_TOKEN
 */
function formatOgDateTime(raw: any): string {
  if (!raw) return "";

  const value = raw?.toDate
    ? raw.toDate()
    : new Date(raw?._seconds ? raw._seconds * 1000 : raw);

  if (Number.isNaN(value.getTime())) return "";

  const days = ["일", "월", "화", "수", "목", "금", "토"];
  const year = value.getFullYear();
  const month = String(value.getMonth() + 1).padStart(2, "0");
  const day = String(value.getDate()).padStart(2, "0");
  const dayName = days[value.getDay()];
  const hour = String(value.getHours()).padStart(2, "0");
  const minute = String(value.getMinutes()).padStart(2, "0");

  return `${year}.${month}.${day} (${dayName}) ${hour}:${minute}`;
}

export const getTicketOgMeta = functions.https.onRequest(async (req, res) => {
  // CORS 허용
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Cache-Control", "public, max-age=300, s-maxage=300");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  const token = req.query.token as string;
  if (!token) { res.status(400).json({ error: "token 필요" }); return; }

  const ticketSnap = await db.collection("mobileTickets")
    .where("accessToken", "==", token)
    .limit(1)
    .get();

  if (ticketSnap.empty) {
    // format=html일 때 기본 OG HTML 반환
    if (req.query.format === "html") {
      const pageUrl = `https://melonticket-web-20260216.vercel.app/m/${token}`;
      const fallbackHtml = `<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<meta property="og:title" content="🎫 멜론티켓">
<meta property="og:description" content="AI 좌석 추천 · 360° 시야 보기 · 모바일 스마트 티켓">
<meta property="og:image" content="https://melonticket-web-20260216.vercel.app/icons/Icon-512.png">
<meta property="og:url" content="${pageUrl}">
<meta property="og:site_name" content="멜론티켓">
<title>멜론티켓</title>
<meta http-equiv="refresh" content="0;url=${pageUrl}">
</head><body></body></html>`;
      res.status(200).set("Content-Type", "text/html; charset=utf-8").send(fallbackHtml);
      return;
    }
    res.status(404).json({ error: "not found" });
    return;
  }

  const ticket = ticketSnap.docs[0].data();
  const eventDoc = await db.collection("events").doc(ticket.eventId).get();
  const event = eventDoc.exists ? eventDoc.data() : null;
  const dateLabel = formatOgDateTime(event?.startAt);
  const description = [
    dateLabel,
    event?.venueName || "",
    "모바일 스마트 티켓",
  ].filter(Boolean).join(" | ");

  const title = event?.title || "공연";
  const imageUrl = event?.ogImageUrl || event?.imageUrl || "";
  const imageAlt = event?.title ? `${event.title} 포스터` : "공연 포스터";
  const seatGrade = ticket.seatGrade || "";

  // format=html → 크롤러용 OG HTML 반환
  if (req.query.format === "html") {
    const pageUrl = `https://melonticket-web-20260216.vercel.app/m/${token}`;
    const ogTitle = `🎫 ${title}`;
    const ogDesc = [seatGrade ? `${seatGrade}석` : "", event?.venueName || "", dateLabel].filter(Boolean).join(" · ");
    const e = (s: string) => s.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    const html = `<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<meta property="og:type" content="website">
<meta property="og:title" content="${e(ogTitle)}">
<meta property="og:description" content="${e(ogDesc)}">
<meta property="og:image" content="${e(imageUrl)}">
<meta property="og:url" content="${e(pageUrl)}">
<meta property="og:site_name" content="멜론티켓">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${e(ogTitle)}">
<meta name="twitter:image" content="${e(imageUrl)}">
<title>${e(ogTitle)}</title>
<meta http-equiv="refresh" content="0;url=${e(pageUrl)}">
</head><body></body></html>`;
    res.status(200).set("Content-Type", "text/html; charset=utf-8").send(html);
    return;
  }

  res.json({
    title,
    description,
    imageUrl: imageUrl || null,
    imageAlt,
    venueName: event?.venueName || "",
    startAt: event?.startAt || null,
    seatGrade,
    siteName: "멜론티켓",
  });
});

// ============================================================
// OG 이미지 생성 (포스터를 1200x630 가로형 캔버스에 배치)
// ============================================================
export const ogImage = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");

  const imageUrl = req.query.url as string;
  if (!imageUrl) {
    res.status(400).send("url 필요");
    return;
  }

  try {
    // 포스터 다운로드
    const response = await fetch(imageUrl);
    if (!response.ok) {
      res.status(404).send("이미지 없음");
      return;
    }
    const posterBuffer = Buffer.from(await response.arrayBuffer());

    // 포스터를 1200x630 캔버스에 배치 (어두운 배경 + 포스터 중앙)
    const W = 1200;
    const H = 630;

    // 포스터를 1200x630에 꽉 채우고 상단부터 크롭
    const result = await sharp(posterBuffer)
      .resize(W, H, { fit: "cover", position: "top" })
      .jpeg({ quality: 85 })
      .toBuffer();

    res.set("Content-Type", "image/jpeg");
    res.set("Cache-Control", "public, max-age=86400, s-maxage=86400");
    res.status(200).send(result);
  } catch (err: any) {
    functions.logger.error("ogImage error:", err.message);
    res.status(500).send("이미지 생성 실패");
  }
});

// ============================================================
// 티켓 데이터 자동 정리 (매일 03:00 KST 실행)
// 공연 종료 30일 후 mobileTickets + checkInLogs 삭제
// ============================================================
export const cleanupExpiredTickets = functions.pubsub
  .schedule("0 18 * * *") // UTC 18:00 = KST 03:00
  .timeZone("Asia/Seoul")
  .onRun(async () => {
    const now = new Date();
    const cutoff = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000); // 30일 전

    // 종료된 이벤트 조회
    const eventsSnap = await db.collection("events")
      .where("startAt", "<", cutoff)
      .get();

    if (eventsSnap.empty) {
      functions.logger.info("cleanupExpiredTickets: 정리할 이벤트 없음");
      return;
    }

    let totalDeleted = 0;

    for (const eventDoc of eventsSnap.docs) {
      const eventId = eventDoc.id;
      const event = eventDoc.data();
      const title = event.title || eventId;

      // 해당 이벤트의 mobileTickets 삭제
      const ticketsSnap = await db.collection("mobileTickets")
        .where("eventId", "==", eventId)
        .limit(500)
        .get();

      if (ticketsSnap.empty) continue;

      const batch = db.batch();
      ticketsSnap.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
      totalDeleted += ticketsSnap.size;

      functions.logger.info(
        `cleanupExpiredTickets: ${title} — ${ticketsSnap.size}건 삭제`
      );
    }

    functions.logger.info(
      `cleanupExpiredTickets: 총 ${totalDeleted}건 삭제 완료`
    );
  });

// ============================================================
// OG 이미지 사전 생성 (이벤트 생성/수정 시 자동)
// ============================================================
export const generateOgImage = functions.firestore
  .document("events/{eventId}")
  .onWrite(async (change, context) => {
    const eventId = context.params.eventId;
    const after = change.after.exists ? change.after.data() : null;
    if (!after) return; // 삭제 시 무시

    const imageUrl = after.imageUrl as string | undefined;
    if (!imageUrl) return;

    // imageUrl이 변경되지 않았으면 스킵
    const before = change.before.exists ? change.before.data() : null;
    if (before?.imageUrl === imageUrl && after.ogImageUrl) return;

    try {
      // 포스터 다운로드
      const response = await fetch(imageUrl);
      if (!response.ok) return;
      const posterBuffer = Buffer.from(await response.arrayBuffer());

      // 1200x630 상단 크롭
      const ogBuffer = await sharp(posterBuffer)
        .resize(1200, 630, { fit: "cover", position: "top" })
        .jpeg({ quality: 85 })
        .toBuffer();

      // Firebase Storage에 저장
      const bucket = admin.storage().bucket();
      const filePath = `events/og/${eventId}.jpg`;
      const file = bucket.file(filePath);
      await file.save(ogBuffer, {
        metadata: { contentType: "image/jpeg", cacheControl: "public, max-age=86400" },
      });
      await file.makePublic();

      const ogImageUrl = `https://storage.googleapis.com/${bucket.name}/${filePath}`;

      // event 문서에 ogImageUrl 저장
      await db.collection("events").doc(eventId).update({ ogImageUrl });

      functions.logger.info(`OG image generated for event ${eventId}: ${ogImageUrl}`);
    } catch (err: any) {
      functions.logger.error(`OG image generation failed for ${eventId}:`, err.message);
    }
  });

/**
 * 모바일 티켓 공개 조회 (비로그인 — accessToken으로 조회)
 */
export const getMobileTicketByToken = functions.https.onCall(async (data: any) => {
  const { accessToken } = data;
  if (!accessToken) {
    throw new functions.https.HttpsError("invalid-argument", "accessToken이 필요합니다");
  }

  const ticketSnap = await db.collection("mobileTickets")
    .where("accessToken", "==", accessToken)
    .limit(1)
    .get();

  if (ticketSnap.empty) {
    throw new functions.https.HttpsError("not-found", "티켓을 찾을 수 없습니다");
  }

  const ticketDoc = ticketSnap.docs[0];
  const ticket = ticketDoc.data();

  // 이벤트 + 그룹 티켓 조회를 병렬로 실행 (성능 최적화)
  const [eventDoc, siblingSnap] = await Promise.all([
    db.collection("events").doc(ticket.eventId).get(),
    ticket.naverOrderId
      ? db.collection("mobileTickets")
          .where("naverOrderId", "==", ticket.naverOrderId)
          .get()
      : Promise.resolve(null),
  ]);

  const event = eventDoc.exists ? eventDoc.data() : null;

  // 그룹 티켓: sibling 처리
  const siblingDocs: Array<{ id: string; data: any }> = [];
  if (siblingSnap && !siblingSnap.empty) {
    let minEntry = Infinity;
    for (const doc of siblingSnap.docs) {
      const en = doc.data().entryNumber || Infinity;
      if (en < minEntry) minEntry = en;
    }
    const isGroupOwner = (ticket.entryNumber || Infinity) === minEntry;

    if (isGroupOwner) {
      for (const doc of siblingSnap.docs) {
        siblingDocs.push({ id: doc.id, data: doc.data() });
      }
    }
  }

  return buildMobileTicketPublicPayload({
    ticketId: ticketDoc.id,
    ticket,
    event,
    siblingDocs,
  });
});

// ============================================================
// 티켓 수신자 이름 설정 (비로그인 — accessToken으로 인증)
// ============================================================

export const setRecipientName = functions.https.onCall(async (data: any) => {
  const { accessToken, recipientName } = data;
  if (!accessToken || !recipientName) {
    throw new functions.https.HttpsError("invalid-argument", "accessToken과 recipientName이 필요합니다");
  }

  if (recipientName.length > 20) {
    throw new functions.https.HttpsError("invalid-argument", "이름은 20자 이하로 입력해주세요");
  }

  const ticketSnap = await db.collection("mobileTickets")
    .where("accessToken", "==", accessToken)
    .limit(1)
    .get();

  if (ticketSnap.empty) {
    throw new functions.https.HttpsError("not-found", "티켓을 찾을 수 없습니다");
  }

  const ticketDoc = ticketSnap.docs[0];
  await ticketDoc.ref.update({ recipientName: recipientName.trim() });

  return { success: true, recipientName: recipientName.trim() };
});

// ============================================================
// 테스트/관리 함수
// ============================================================

/**
 * 좌석 즉시 공개 (revealAt을 현재 시각으로 설정)
 */
export const revealSeatsNow = functions.https.onCall(async (data: any, context) => {
  await assertAdmin(context?.auth?.uid);
  const { eventId } = data;
  if (!eventId) {
    throw new functions.https.HttpsError("invalid-argument", "eventId가 필요합니다");
  }

  const now = admin.firestore.Timestamp.now();
  await db.collection("events").doc(eventId).update({ revealAt: now });

  return { success: true, revealAt: now.toDate().toISOString() };
});

/**
 * 좌석 재배정 (티켓의 좌석을 다른 좌석으로 변경)
 */
export const reassignTicketSeat = functions.https.onCall(async (data: any, context) => {
  await assertAdmin(context?.auth?.uid);
  const { ticketId, newSeatId } = data;
  if (!ticketId || !newSeatId) {
    throw new functions.https.HttpsError("invalid-argument", "ticketId와 newSeatId가 필요합니다");
  }

  const ticketRef = db.collection("mobileTickets").doc(ticketId);
  const ticketDoc = await ticketRef.get();
  if (!ticketDoc.exists) {
    throw new functions.https.HttpsError("not-found", "티켓을 찾을 수 없습니다");
  }
  const ticket = ticketDoc.data()!;

  // 새 좌석 확인
  const newSeatRef = db.collection("seats").doc(newSeatId);
  const newSeatDoc = await newSeatRef.get();
  if (!newSeatDoc.exists) {
    throw new functions.https.HttpsError("not-found", "좌석을 찾을 수 없습니다");
  }
  const newSeat = newSeatDoc.data()!;

  if (newSeat.status !== "available") {
    throw new functions.https.HttpsError("failed-precondition", "이미 배정된 좌석입니다");
  }

  const batch = db.batch();
  const reassignedAt = admin.firestore.Timestamp.now();

  // 기존 좌석 해제
  if (ticket.seatId) {
    batch.update(db.collection("seats").doc(ticket.seatId), {
      status: "available",
      ticketId: null,
    });
  }

  // 새 좌석 배정
  batch.update(newSeatRef, {
    status: "reserved",
    ticketId: ticketId,
  });

  // seatInfo 생성
  const floor = newSeat.floor || "";
  const block = newSeat.block || "";
  const row = newSeat.row || "";
  const number = newSeat.number || "";
  const seatInfo = [floor, block ? `${block}블록` : "", row ? `${row}열` : "", number ? `${number}번` : ""]
    .filter(Boolean).join(" ");

  // 티켓 업데이트
  batch.update(ticketRef, {
    seatId: newSeatId,
    seatNumber: `${newSeat.number}`,
    seatInfo: seatInfo,
    previousSeatId: ticket.seatId || null,
    previousSeatInfo: ticket.seatInfo || null,
    seatReassignedAt: reassignedAt,
    seatReassignHistory: admin.firestore.FieldValue.arrayUnion({
      fromSeatId: ticket.seatId || null,
      fromSeatInfo: ticket.seatInfo || null,
      toSeatId: newSeatId,
      toSeatInfo: seatInfo,
      changedAt: reassignedAt,
    }),
  });

  await batch.commit();

  return { success: true, seatInfo };
});

// ============================================================
// 봇 연동용 HTTP 엔드포인트 (API 키 인증)
// ============================================================

/**
 * 봇에서 호출하는 네이버 주문 생성 HTTP 엔드포인트
 * POST /createNaverOrderHttp
 * Header: Authorization: Bearer {BOT_API_KEY}
 * Body: { eventId, naverOrderId, buyerName, buyerPhone, productName, seatGrade, quantity, orderDate?, memo? }
 */
export const createNaverOrderHttp = functions.https.onRequest(async (req, res) => {
  // CORS
  res.set("Access-Control-Allow-Origin", "*");
  if (req.method === "OPTIONS") {
    res.set("Access-Control-Allow-Methods", "POST");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
    res.status(204).send("");
    return;
  }

  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  if (!requireBotRequestAuth(req, res)) {
    return;
  }

  try {
    const result = await createNaverOrderInternal(req.body, { logPrefix: "[봇] " });
    res.status(200).json(result);
  } catch (err: any) {
    sendHttpError(res, err, "createNaverOrderHttp 오류:");
  }
});

/**
 * 봇에서 이벤트 목록 조회용 HTTP 엔드포인트
 */
export const listEventsHttp = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  if (!requireBotRequestAuth(req, res)) {
    return;
  }

  const snap = await db.collection("events").orderBy("startAt", "desc").get();
  const events = snap.docs.map((doc) => {
    const d = doc.data();
    const startAt = toDate(d.startAt) || toDate(d.date);
    return {
      id: doc.id,
      title: d.title || "",
      venueName: d.venueName || "",
      date: startAt ? startAt.toISOString() : "",
      naverOnly: d.naverOnly === true,
      naverProductKeyword: d.naverProductKeyword || "",
    };
  });
  res.status(200).json({ events });
});

/**
 * 봇에서 특정 이벤트의 네이버 주문 목록 조회
 * POST /listNaverOrdersHttp
 * Body: { eventId } or {} (전체)
 */
export const listNaverOrdersHttp = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  if (!requireBotRequestAuth(req, res)) {
    return;
  }

  try {
    const { eventId } = req.body || {};
    let query: FirebaseFirestore.Query = db.collection("naverOrders");

    if (eventId) {
      query = query.where("eventId", "==", eventId);
    }

    query = query.orderBy("createdAt", "desc").limit(500);
    const snap = await query.get();

    const orders = snap.docs.map((doc) => {
      const d = doc.data();
      return {
        id: doc.id,
        naverOrderId: d.naverOrderId || "",
        eventId: d.eventId || "",
        buyerName: d.buyerName || "",
        buyerPhone: d.buyerPhone || "",
        productName: d.productName || "",
        seatGrade: d.seatGrade || "",
        quantity: d.quantity || 1,
        status: d.status || "",
        createdAt: toDate(d.createdAt)?.toISOString() || "",
        ticketCount: d.ticketIds?.length || 0,
      };
    });

    res.status(200).json({ orders });
  } catch (err: any) {
    sendHttpError(res, err, "listNaverOrdersHttp 오류:");
  }
});

/**
 * 봇 SMS 폴링 — 대기중 SMS 태스크 가져오기
 * GET /getPendingSmsHttp
 */
export const getPendingSmsHttp = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  if (!requireBotRequestAuth(req, res)) {
    return;
  }

  const snap = await db.collection("smsTasks")
    .where("status", "==", "pending")
    .orderBy("priority")
    .orderBy("createdAt")
    .limit(10)
    .get();

  const tasks = snap.docs.map((doc) => {
    const d = doc.data();
    return {
      id: doc.id,
      type: d.type || "orderConfirm",
      buyerName: d.buyerName || "",
      buyerPhone: d.buyerPhone || "",
      productName: d.productName || "",
      seatGrade: d.seatGrade || "",
      quantity: d.quantity || 1,
      ticketUrls: d.ticketUrls || [],
      priority: d.priority || 1,
    };
  });

  res.status(200).json({ tasks });
});

/**
 * 봇 SMS 발송 결과 보고
 * POST /markSmsSentHttp
 * Body: { taskId, status: "sent" | "failed", error?: string }
 */
export const markSmsSentHttp = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  if (!requireBotRequestAuth(req, res)) {
    return;
  }

  const { taskId, status, error } = req.body;
  if (!taskId || !status) {
    res.status(400).json({ error: "taskId와 status 필요" });
    return;
  }

  const updateData: any = { status };
  if (status === "sent") {
    updateData.sentAt = admin.firestore.Timestamp.now();
  }
  if (error) {
    updateData.error = error;
  }

  await db.collection("smsTasks").doc(taskId).update(updateData);
  res.status(200).json({ success: true });
});

/**
 * 봇용 — 네이버 주문번호로 취소 처리
 * POST /cancelNaverOrderHttp
 * Body: { naverOrderId }
 */
export const cancelNaverOrderHttp = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  if (!requireBotRequestAuth(req, res)) {
    return;
  }

  try {
    const naverOrderId = typeof req.body?.naverOrderId === "string" ? req.body.naverOrderId.trim() : "";
    if (!naverOrderId) {
      throw new functions.https.HttpsError("invalid-argument", "naverOrderId 필요");
    }

    const orderDoc = await getNaverOrderDocByNaverOrderId(naverOrderId);
    const result = await cancelNaverOrderInternal(orderDoc, {
      allowAlreadyCancelled: true,
      logPrefix: "봇 자동 ",
    });
    res.status(200).json(result);
  } catch (err: any) {
    sendHttpError(res, err, "cancelNaverOrderHttp 오류:");
  }
});

/**
 * 네이버 스토어 상품 정보 크롤링 (공개 페이지)
 * POST /scrapeNaverProductHttp
 * Body: { url } — e.g. "https://smartstore.naver.com/storename/products/12345"
 */
export const scrapeNaverProductHttp = functions
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onRequest(async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }

    const authHeader = req.headers.authorization || "";
    const token = getBearerToken(authHeader);
    // Admin Firebase Auth token 또는 BOT_API_KEY
    const botApiKey = getOptionalBotApiKey();
    let isAuthed = botApiKey != null && token === botApiKey;
    if (!isAuthed) {
      try {
        await admin.auth().verifyIdToken(token);
        isAuthed = true;
      } catch { /* not a valid firebase token */ }
    }
    if (!isAuthed) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }

    const { url } = req.body;
    if (!url) {
      res.status(400).json({ error: "url 필요" });
      return;
    }

    try {
      // 네이버 스마트스토어 상품 페이지 HTML fetch
      const response = await fetch(url, {
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          "Accept-Language": "ko-KR,ko;q=0.9",
        },
      });

      if (!response.ok) {
        res.status(400).json({ error: `페이지 요청 실패: ${response.status}` });
        return;
      }

      const html = await response.text();

      // 네이버 스마트스토어는 window.__PRELOADED_STATE__ 에 JSON 데이터를 넣어둠
      const stateMatch = html.match(/window\.__PRELOADED_STATE__\s*=\s*(".*?")\s*[;<]/);
      let product: any = {};

      if (stateMatch) {
        try {
          // JSON-encoded string inside quotes — need double parse
          const jsonStr = JSON.parse(stateMatch[1]);
          const state = JSON.parse(jsonStr);

          const productInfo = state?.product?.A || state?.product?.a || {};
          const channel = state?.channel || {};

          product = {
            title: productInfo.name || "",
            price: productInfo.salePrice || productInfo.price || 0,
            imageUrl: productInfo.representImage?.url || productInfo.productImages?.[0]?.url || "",
            options: (productInfo.optionCombinations || []).map((opt: any) => ({
              name: opt.optionName1 || opt.name || "",
              price: opt.price || productInfo.salePrice || 0,
              stockQuantity: opt.stockQuantity ?? null,
            })),
            storeName: channel.channelName || "",
          };
        } catch (parseErr: any) {
          functions.logger.warn("PRELOADED_STATE 파싱 실패:", parseErr.message);
        }
      }

      // fallback: OG 태그에서 추출
      if (!product.title) {
        const ogTitle = html.match(/<meta\s+property="og:title"\s+content="([^"]+)"/);
        product.title = ogTitle?.[1] || "";
      }
      if (!product.imageUrl) {
        const ogImage = html.match(/<meta\s+property="og:image"\s+content="([^"]+)"/);
        product.imageUrl = ogImage?.[1] || "";
      }
      if (!product.price) {
        const priceMatch = html.match(/<meta\s+property="product:price:amount"\s+content="(\d+)"/);
        product.price = priceMatch ? parseInt(priceMatch[1]) : 0;
      }

      res.status(200).json({ success: true, product });
    } catch (err: any) {
      functions.logger.error("스크래핑 에러:", err);
      res.status(500).json({ error: err.message || "스크래핑 실패" });
    }
  });

/**
 * 봇이 스크래핑한 네이버 상품 목록을 Firestore에 동기화
 * POST /syncNaverProductsHttp
 * Body: { products: [{ name, price, productNo }] }
 */
export const syncNaverProductsHttp = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  if (!requireBotRequestAuth(req, res)) {
    return;
  }

  const { products } = req.body;
  if (!Array.isArray(products)) {
    res.status(400).json({ error: "products 배열 필요" });
    return;
  }

  try {
    const batch = db.batch();
    const now = admin.firestore.Timestamp.now();

    for (const p of products) {
      const docId = String(p.productNo || p.name).replace(/[\/\s]/g, "_");
      if (!docId) continue;
      const ref = db.collection("naverProducts").doc(docId);
      batch.set(ref, {
        productNo: p.productNo || "",
        name: p.name || "",
        price: p.price || 0,
        url: `https://smartstore.naver.com/melon_symphony_orchestra/products/${p.productNo || ""}`,
        syncedAt: now,
      }, { merge: true });
    }

    await batch.commit();

    functions.logger.info(`네이버 상품 동기화: ${products.length}개`);
    res.status(200).json({ success: true, synced: products.length });
  } catch (err: any) {
    functions.logger.error("상품 동기화 에러:", err);
    res.status(500).json({ error: err.message });
  }
});

// ── 카카오 주소/키워드 검색 프록시 (CORS 우회) ──
export const searchAddressHttp = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  const query = req.query.q as string;
  if (!query) { res.status(400).json({ error: "q parameter required" }); return; }

  const kakaoKey = "8e3ecb0f10cd15fc7a7760a4f87e2cbb";
  const encoded = encodeURIComponent(query);
  const headers = { Authorization: `KakaoAK ${kakaoKey}` };

  try {
    const [kwRes, addrRes] = await Promise.all([
      fetch(`https://dapi.kakao.com/v2/local/search/keyword.json?query=${encoded}&size=10`, { headers }),
      fetch(`https://dapi.kakao.com/v2/local/search/address.json?query=${encoded}&size=5`, { headers }),
    ]);

    const kwData: any = await kwRes.json();
    const addrData: any = await addrRes.json();

    const results: any[] = [];

    // 주소 검색 결과 (상단)
    for (const d of (addrData.documents || [])) {
      const road = d.road_address;
      results.push({
        place_name: road?.building_name || d.address_name || "",
        road_address_name: road?.address_name || "",
        address_name: d.address_name || "",
        phone: "",
        _type: "address",
      });
    }

    // 키워드 검색 결과
    for (const d of (kwData.documents || [])) {
      results.push({
        place_name: d.place_name || "",
        road_address_name: d.road_address_name || "",
        address_name: d.address_name || "",
        phone: d.phone || "",
        _type: "keyword",
      });
    }

    res.status(200).json({ results });
  } catch (err: any) {
    functions.logger.error("카카오 검색 에러:", err);
    res.status(500).json({ error: err.message });
  }
});

// ============================================================
// Excel .xls → .xlsx 변환
// ============================================================

/**
 * POST /convertXlsToXlsxHttp
 * Body: { base64: "..." }  (원본 엑셀 base64)
 * Returns: { base64: "..." } (변환된 .xlsx base64)
 */
export const convertXlsToXlsxHttp = functions
  .runWith({ memory: "512MB", timeoutSeconds: 30 })
  .https.onRequest(async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }

    try {
      const inputBase64 = req.body?.base64;
      if (!inputBase64 || typeof inputBase64 !== "string") {
        res.status(400).json({ error: "base64 필드가 필요합니다" });
        return;
      }

      const inputBuffer = Buffer.from(inputBase64, "base64");

      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const XLSX = require("xlsx");
      const workbook = XLSX.read(inputBuffer, {
        type: "buffer",
        cellStyles: true,
        cellNF: false,
      });

      // numFmt 메타데이터 제거 — Dart excel 패키지 호환성 문제 방지
      for (const sheetName of workbook.SheetNames) {
        const sheet = workbook.Sheets[sheetName];
        for (const cellAddr of Object.keys(sheet)) {
          if (cellAddr.startsWith("!")) continue;
          const cell = sheet[cellAddr];
          if (cell) {
            delete cell.z; // number format 제거
          }
        }
      }

      const outputBuffer = XLSX.write(workbook, { type: "buffer", bookType: "xlsx" });

      res.status(200).json({
        base64: Buffer.from(outputBuffer).toString("base64"),
      });
    } catch (err: any) {
      functions.logger.error("Excel 변환 에러:", err);
      res.status(500).json({ error: `변환 실패: ${err.message}` });
    }
  });

// ============================================================
// 봇 좌석 배정 결과 → mobileTickets 반영
// ============================================================

/**
 * POST /updateTicketSeatsHttp
 * Header: Authorization: Bearer {BOT_API_KEY}
 * Body: {
 *   eventId: string,
 *   assignments: [
 *     {
 *       naverOrderId?: string,
 *       buyerName: string,
 *       buyerPhone?: string,
 *       seatGrade: string,        // "VIP", "R", "S", "A"
 *       seats: [
 *         { floor: "1층", section: "B구역", row: 3, number: 15 },
 *         ...
 *       ]
 *     }
 *   ]
 * }
 */
export const updateTicketSeatsHttp = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { res.status(405).json({ error: "Method not allowed" }); return; }
  if (!requireBotRequestAuth(req, res)) return;

  const { eventId, assignments } = req.body;
  if (!eventId || !Array.isArray(assignments) || assignments.length === 0) {
    res.status(400).json({ error: "eventId와 assignments 배열이 필요합니다" });
    return;
  }

  try {
    let updated = 0;
    let skipped = 0;
    const errors: string[] = [];

    for (const assign of assignments) {
      const { naverOrderId, buyerName, seatGrade, seats } = assign;
      if (!buyerName || !seatGrade || !Array.isArray(seats) || seats.length === 0) {
        errors.push(`${buyerName || "?"}: 필수 필드 누락`);
        skipped++;
        continue;
      }

      // 1. naverOrderId로 먼저 찾기
      let ticketDocs: admin.firestore.QueryDocumentSnapshot[] = [];
      if (naverOrderId) {
        const orderSnap = await db.collection("naverOrders")
          .where("naverOrderId", "==", naverOrderId)
          .where("eventId", "==", eventId)
          .limit(1).get();

        if (!orderSnap.empty) {
          const orderData = orderSnap.docs[0].data();
          const ticketIds: string[] = orderData.ticketIds || [];
          for (const tid of ticketIds) {
            const tDoc = await db.collection("mobileTickets").doc(tid).get();
            if (tDoc.exists && tDoc.data()?.status === "active") {
              ticketDocs.push(tDoc as admin.firestore.QueryDocumentSnapshot);
            }
          }
        }
      }

      // 2. naverOrderId 매칭 실패 시 buyerName + seatGrade로 검색
      if (ticketDocs.length === 0) {
        const ticketSnap = await db.collection("mobileTickets")
          .where("eventId", "==", eventId)
          .where("buyerName", "==", buyerName)
          .where("seatGrade", "==", seatGrade)
          .where("status", "==", "active")
          .get();
        ticketDocs = ticketSnap.docs;
      }

      if (ticketDocs.length === 0) {
        errors.push(`${buyerName}(${seatGrade}): 티켓 없음`);
        skipped++;
        continue;
      }

      // 3. 좌석 배정 — 티켓 수와 좌석 수 매칭
      const batch = db.batch();
      const now = admin.firestore.Timestamp.now();
      const seatsToAssign = seats.slice(0, ticketDocs.length);

      for (let i = 0; i < Math.min(ticketDocs.length, seatsToAssign.length); i++) {
        const tDoc = ticketDocs[i];
        const s = seatsToAssign[i];
        const seatInfo = [
          s.floor || "",
          s.section || "",
          s.row ? `${s.row}열` : "",
          s.number ? `${s.number}번` : "",
        ].filter(Boolean).join(" ");

        batch.update(tDoc.ref, {
          seatInfo,
          seatNumber: s.number ? `${s.number}` : "",
          seatAssignedAt: now,
          seatAssignedBy: "bot",
        });
      }

      await batch.commit();
      updated += seatsToAssign.length;
    }

    functions.logger.info(`좌석 배정 완료: ${updated}매 업데이트, ${skipped}건 스킵`);
    res.status(200).json({ success: true, updated, skipped, errors });
  } catch (err: any) {
    sendHttpError(res, err, "updateTicketSeatsHttp 오류:");
  }
});

// ============================================================
// 공연종료 (어드민 → 이벤트 상태를 completed로 변경)
// ============================================================
export const completeEvent = functions.https.onCall(async (data: any, context) => {
  await assertAdmin(context?.auth?.uid);
  const { eventId } = data;
  if (!eventId) {
    throw new functions.https.HttpsError("invalid-argument", "eventId가 필요합니다");
  }

  await db.collection("events").doc(eventId).update({
    eventStatus: "completed",
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { success: true };
});

// ============================================================
// 리뷰 제출 (모바일 티켓 → accessToken 인증)
// ============================================================
export const submitReview = functions.https.onCall(async (data: any) => {
  const { ticketId, accessToken, rating, comment } = data;

  if (!ticketId || !accessToken || !rating) {
    throw new functions.https.HttpsError("invalid-argument", "ticketId, accessToken, rating이 필요합니다");
  }

  if (typeof rating !== "number" || rating < 1 || rating > 5) {
    throw new functions.https.HttpsError("invalid-argument", "rating은 1~5 사이여야 합니다");
  }

  // accessToken으로 티켓 소유 확인
  const ticketRef = db.collection("mobileTickets").doc(ticketId);
  const ticketDoc = await ticketRef.get();

  if (!ticketDoc.exists) {
    throw new functions.https.HttpsError("not-found", "티켓을 찾을 수 없습니다");
  }

  const ticket = ticketDoc.data()!;
  if (ticket.accessToken !== accessToken) {
    throw new functions.https.HttpsError("permission-denied", "접근 권한이 없습니다");
  }

  // 중복 리뷰 체크
  const existingReview = await db.collection("reviews")
    .where("ticketId", "==", ticketId)
    .limit(1)
    .get();

  if (!existingReview.empty) {
    throw new functions.https.HttpsError("already-exists", "이미 리뷰를 작성하셨습니다");
  }

  // 리뷰 저장
  await db.collection("reviews").add({
    ticketId,
    eventId: ticket.eventId,
    buyerName: ticket.buyerName || "",
    recipientName: ticket.recipientName || null,
    rating,
    comment: typeof comment === "string" ? comment.trim().slice(0, 200) : "",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { success: true };
});

// ============================================================
// 스캐너 오프라인 캐시용 — 이벤트 전체 티켓 다운로드
// ============================================================
export const downloadEventTicketsForScanner = functions.https.onCall(async (data: any, context) => {
  await assertStaffOrAdmin(context?.auth?.uid);
  const { eventId } = data;
  if (!eventId || typeof eventId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "eventId가 필요합니다");
  }

  const eventDoc = await db.collection("events").doc(eventId).get();
  if (!eventDoc.exists) {
    throw new functions.https.HttpsError("not-found", "이벤트를 찾을 수 없습니다");
  }
  const event = eventDoc.data()!;

  // 일반 티켓 (tickets 컬렉션)
  const ticketSnaps = await db.collection("tickets")
    .where("eventId", "==", eventId)
    .get();

  const tickets = ticketSnaps.docs.map(doc => {
    const d = doc.data();
    return {
      id: doc.id,
      type: "ticket" as const,
      eventId: d.eventId,
      status: d.status || "issued",
      qrVersion: d.qrVersion || 1,
      seatInfo: d.seatInfo || null,
      seatGrade: d.seatGrade || null,
      buyerName: d.buyerName || null,
      phoneLast4: d.phoneLast4 || (d.buyerPhone ? d.buyerPhone.slice(-4) : null),
      entryNumber: d.entryNumber || null,
      entryCheckedInAt: d.entryCheckedInAt ? d.entryCheckedInAt.toDate().toISOString() : null,
      intermissionCheckedInAt: d.intermissionCheckedInAt ? d.intermissionCheckedInAt.toDate().toISOString() : null,
    };
  });

  // 모바일 티켓 (mobileTickets 컬렉션)
  const mobileSnaps = await db.collection("mobileTickets")
    .where("eventId", "==", eventId)
    .get();

  const mobileTickets = mobileSnaps.docs.map(doc => {
    const d = doc.data();
    return {
      id: doc.id,
      type: "mobile" as const,
      eventId: d.eventId,
      status: d.status || "active",
      qrVersion: d.qrVersion || 1,
      seatInfo: d.seatInfo || null,
      seatGrade: d.seatGrade || null,
      buyerName: d.buyerName || null,
      phoneLast4: d.buyerPhone ? d.buyerPhone.slice(-4) : null,
      entryNumber: d.entryNumber || null,
      accessToken: d.accessToken || null,
      entryCheckedInAt: d.entryCheckedInAt ? d.entryCheckedInAt.toDate().toISOString() : null,
      intermissionCheckedInAt: d.intermissionCheckedInAt ? d.intermissionCheckedInAt.toDate().toISOString() : null,
    };
  });

  return {
    success: true,
    eventId,
    eventTitle: event.title || "",
    totalTickets: tickets.length,
    totalMobileTickets: mobileTickets.length,
    tickets,
    mobileTickets,
    downloadedAt: new Date().toISOString(),
  };
});

// ============================================================
// 오프라인 체크인 일괄 동기화
// ============================================================
export const syncOfflineCheckins = functions.https.onCall(async (data: any, context) => {
  await assertStaffOrAdmin(context?.auth?.uid);
  const { checkins } = data;
  if (!Array.isArray(checkins) || checkins.length === 0) {
    throw new functions.https.HttpsError("invalid-argument", "체크인 배열이 필요합니다");
  }

  const batch = db.batch();
  let synced = 0;
  let skipped = 0;
  const errors: string[] = [];

  for (const entry of checkins) {
    const { ticketId, eventId, checkinStage, checkedInAt } = entry;
    if (!ticketId || !eventId || !checkinStage) {
      skipped++;
      continue;
    }

    try {
      const isMobile = ticketId.startsWith("mt_");
      const actualId = isMobile ? ticketId.replace("mt_", "") : ticketId;
      const collection = isMobile ? "mobileTickets" : "tickets";
      const ticketRef = db.collection(collection).doc(actualId);
      const ticketDoc = await ticketRef.get();

      if (!ticketDoc.exists) {
        skipped++;
        errors.push(`${ticketId}: 티켓 없음`);
        continue;
      }

      const ticket = ticketDoc.data()!;
      const fieldPrefix = checkinStage === "entry" ? "entry" : "intermission";
      const checkinField = `${fieldPrefix}CheckedInAt`;

      // 이미 체크인된 경우 스킵
      if (ticket[checkinField]) {
        skipped++;
        continue;
      }

      const syncTime = checkedInAt ? new Date(checkedInAt) : new Date();
      const updateData: Record<string, any> = {
        [checkinField]: admin.firestore.Timestamp.fromDate(syncTime),
        [`${fieldPrefix}CheckinStaffId`]: context?.auth?.uid || "offline-sync",
      };

      if (checkinStage === "intermission") {
        updateData.status = isMobile ? "used" : "used";
        updateData.usedAt = admin.firestore.Timestamp.fromDate(syncTime);
      }

      batch.update(ticketRef, updateData);

      // 체크인 로그
      const logRef = db.collection("checkins").doc();
      batch.set(logRef, {
        ticketId: actualId,
        eventId,
        staffId: context?.auth?.uid || "offline-sync",
        scannerDeviceId: "offline-sync",
        stage: checkinStage,
        result: "success",
        seatInfo: ticket.seatInfo || null,
        scannedAt: admin.firestore.Timestamp.fromDate(syncTime),
        isOfflineSync: true,
      });

      synced++;
    } catch (err: any) {
      skipped++;
      errors.push(`${ticketId}: ${err.message}`);
    }
  }

  await batch.commit();

  return {
    success: true,
    synced,
    skipped,
    errors: errors.slice(0, 10), // 최대 10개 에러만 반환
  };
});