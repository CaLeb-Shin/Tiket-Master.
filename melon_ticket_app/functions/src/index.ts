import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import * as jwt from "jsonwebtoken";

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
  const role = await getUserRole(uid);
  if (role !== "admin") {
    throw new functions.https.HttpsError("permission-denied", "관리자 권한이 필요합니다");
  }
  return uid;
}

async function assertStaffOrAdmin(uid?: string): Promise<string> {
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
  }
  const role = await getUserRole(uid);
  if (role !== "admin" && role !== "staff") {
    throw new functions.https.HttpsError("permission-denied", "스태프 권한이 필요합니다");
  }
  return uid;
}

type CheckinStage = "entry" | "intermission";

function normalizeCheckinStage(value: unknown): CheckinStage {
  return value === "intermission" ? "intermission" : "entry";
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

  // 선호 좌석 포함 우선 + 중앙 근접 좌석 우선
  const preferredSet = new Set(preferredSeatIds);
  const numbers = seats.map((s) => s.number);
  const minNumber = Math.min(...numbers);
  const maxNumber = Math.max(...numbers);
  const center = (minNumber + maxNumber) / 2;

  candidates.sort((a, b) => {
    const aPreferred = a.reduce((count, seat) => count + (preferredSet.has(seat.id) ? 1 : 0), 0);
    const bPreferred = b.reduce((count, seat) => count + (preferredSet.has(seat.id) ? 1 : 0), 0);
    if (aPreferred !== bPreferred) {
      return bPreferred - aPreferred;
    }

    const aAvg = a.reduce((sum, seat) => sum + seat.number, 0) / a.length;
    const bAvg = b.reduce((sum, seat) => sum + seat.number, 0) / b.length;
    const aDist = Math.abs(aAvg - center);
    const bDist = Math.abs(bAvg - center);
    return aDist - bDist;
  });

  return candidates[0];
}

// ============================================================
// 3. revealSeatsForEvent - 좌석 공개 (공연 1시간 전)
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
  const scannerUid = await assertStaffOrAdmin(context?.auth?.uid);
  const { deviceId, label, platform } = data ?? {};

  if (!deviceId || typeof deviceId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "기기 ID가 필요합니다");
  }

  const trimmedId = deviceId.trim();
  if (trimmedId.length < 8 || trimmedId.length > 128) {
    throw new functions.https.HttpsError("invalid-argument", "유효하지 않은 기기 ID입니다");
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

  // admin 역할이면 신규 등록 시 자동 승인
  const userRole = await getUserRole(scannerUid);
  const approved = existingDoc.exists
    ? existing.approved === true
    : userRole === "admin";
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
      message: result === "expired" ? "QR이 만료되었습니다" : "잘못된 QR입니다",
    };
  }

  // 티켓 ID 일치 확인
  if (decoded.ticketId !== ticketId) {
    await logCheckin(ticketId, actorStaffId, "invalidTicket", "티켓 ID 불일치", {
      stage: checkinStage,
      scannerDeviceId,
      eventId: decoded?.eventId,
    });
    return {
      success: false,
      result: "invalidTicket",
      message: "잘못된 티켓입니다",
    };
  }

  // 트랜잭션으로 체크인 처리
  return db.runTransaction(async (transaction) => {
    const ticketRef = db.collection("tickets").doc(ticketId);
    const ticketDoc = await transaction.get(ticketRef);

    if (!ticketDoc.exists) {
      await logCheckin(ticketId, actorStaffId, "invalidTicket", "티켓 없음", {
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
        message: "재발급된 QR입니다. 최신 QR을 사용해주세요",
      };
    }

    if (ticket.status === "canceled") {
      await logCheckin(ticketId, actorStaffId, "canceled", "취소된 티켓", {
        stage: checkinStage,
        scannerDeviceId,
        eventId,
      });
      return {
        success: false,
        result: "canceled",
        message: "취소된 티켓입니다",
      };
    }

    const entryCheckedInAt = ticket.entryCheckedInAt;
    const intermissionCheckedInAt = ticket.intermissionCheckedInAt;

    if (checkinStage === "entry") {
      if (entryCheckedInAt || ticket.status === "used" || intermissionCheckedInAt) {
        await logCheckin(ticketId, actorStaffId, "alreadyUsed", "1차 입장 이미 완료", {
          stage: checkinStage,
          scannerDeviceId,
          eventId,
        });
        return {
          success: false,
          result: "alreadyUsed",
          message: "이미 1차 입장이 완료된 티켓입니다",
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
          message: "1차 입장 체크 후 인터미션 재입장을 처리할 수 있습니다",
        };
      }
      if (intermissionCheckedInAt || ticket.status === "used") {
        await logCheckin(ticketId, actorStaffId, "alreadyUsed", "2차 입장 이미 완료", {
          stage: checkinStage,
          scannerDeviceId,
          eventId,
        });
        return {
          success: false,
          result: "alreadyUsed",
          message: "이미 2차 입장까지 완료된 티켓입니다",
        };
      }
    }

    // 좌석 정보 조회
    const seatDoc = await transaction.get(db.collection("seats").doc(ticket.seatId));
    const seat = seatDoc.data();
    const seatInfo = seat
      ? `${seat.block}구역 ${seat.floor} ${seat.row || ""}열 ${seat.number}번`
      : "좌석 정보 없음";

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

    if (seatDoc.exists) {
      transaction.update(seatDoc.ref, { status: "used" });
    }

    const checkinRef = db.collection("checkins").doc();
    transaction.set(checkinRef, {
      eventId,
      ticketId,
      staffId: actorStaffId,
      scannerDeviceId,
      stage: checkinStage,
      result: "success",
      seatInfo,
      scannedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    functions.logger.info(
      `체크인 성공: 티켓 ${ticketId}, 단계=${checkinStage}, 좌석=${seatInfo}, device=${scannerDeviceId}`
    );

    return {
      success: true,
      result: "success",
      title: checkinStage === "entry" ? "1차 입장 확인" : "2차 재입장 확인",
      message: checkinStage === "entry" ? "초기 입장 체크 완료" : "인터미션 재입장 체크 완료",
      seatInfo,
      stage: checkinStage,
      ticketStatus: checkinStage === "entry" ? "entryCheckedIn" : "used",
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
