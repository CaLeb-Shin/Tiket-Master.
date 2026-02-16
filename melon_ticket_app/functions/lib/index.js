"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.scheduledRevealSeats = exports.verifyAndCheckIn = exports.issueQrToken = exports.requestTicketCancellation = exports.revealSeatsForEvent = exports.confirmPaymentAndAssignSeats = exports.createOrder = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const jwt = __importStar(require("jsonwebtoken"));
admin.initializeApp();
const db = admin.firestore();
// JWT 시크릿 (실제 운영 시 환경 변수로 관리)
const JWT_SECRET = process.env.JWT_SECRET || "melon-ticket-secret-key-change-in-production";
const QR_TOKEN_EXPIRY = 120; // 2분
const REFUND_FULL_HOURS = 24;
const REFUND_PARTIAL_HOURS = 3;
async function getUserRole(uid) {
    const userDoc = await db.collection("users").doc(uid).get();
    return userDoc.data()?.role ?? "user";
}
async function assertAdmin(uid) {
    if (!uid) {
        throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
    }
    const role = await getUserRole(uid);
    if (role !== "admin") {
        throw new functions.https.HttpsError("permission-denied", "관리자 권한이 필요합니다");
    }
    return uid;
}
async function assertStaffOrAdmin(uid) {
    if (!uid) {
        throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
    }
    const role = await getUserRole(uid);
    if (role !== "admin" && role !== "staff") {
        throw new functions.https.HttpsError("permission-denied", "스태프 권한이 필요합니다");
    }
    return uid;
}
function toDate(value) {
    if (!value)
        return null;
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
// 1. createOrder - 주문 생성
// ============================================================
exports.createOrder = functions.https.onCall(async (request) => {
    const { eventId, quantity } = request.data;
    const userId = request.auth?.uid;
    const preferredSeatIds = Array.isArray(request.data?.preferredSeatIds)
        ? [...new Set(request.data.preferredSeatIds.filter((v) => typeof v === "string"))]
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
    const event = eventDoc.data();
    // 구매 가능 여부 확인
    if (quantity > event.maxTicketsPerOrder) {
        throw new functions.https.HttpsError("invalid-argument", `최대 ${event.maxTicketsPerOrder}매까지 구매 가능합니다`);
    }
    if (quantity > event.availableSeats) {
        throw new functions.https.HttpsError("resource-exhausted", "잔여 좌석이 부족합니다");
    }
    const normalizedPreferred = preferredSeatIds.slice(0, quantity);
    // 주문 생성
    const orderRef = db.collection("orders").doc();
    const order = {
        eventId,
        userId,
        quantity,
        unitPrice: event.price,
        totalAmount: event.price * quantity,
        preferredSeatIds: normalizedPreferred,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await orderRef.set(order);
    functions.logger.info(`주문 생성: ${orderRef.id}, 수량: ${quantity}`);
    return {
        success: true,
        orderId: orderRef.id,
        totalAmount: order.totalAmount,
    };
});
// ============================================================
// 2. confirmPaymentAndAssignSeats - 결제 확정 및 연속좌석 배정 (핵심!)
// ============================================================
exports.confirmPaymentAndAssignSeats = functions.https.onCall(async (request) => {
    const { orderId } = request.data;
    const userId = request.auth?.uid;
    if (!userId) {
        throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
    }
    // 트랜잭션으로 원자성 보장 (1500석 규모 성능 고려)
    return db.runTransaction(async (transaction) => {
        // 주문 조회
        const orderRef = db.collection("orders").doc(orderId);
        const orderDoc = await transaction.get(orderRef);
        if (!orderDoc.exists) {
            throw new functions.https.HttpsError("not-found", "주문을 찾을 수 없습니다");
        }
        const order = orderDoc.data();
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
        // 연속좌석 찾기
        const eventId = order.eventId;
        const quantity = order.quantity;
        // 가용 좌석 조회 (인덱스: eventId + status)
        const seatsSnapshot = await transaction.get(db.collection("seats")
            .where("eventId", "==", eventId)
            .where("status", "==", "available")
            .orderBy("block")
            .orderBy("floor")
            .orderBy("row")
            .orderBy("number"));
        const availableSeats = seatsSnapshot.docs.map((doc) => ({
            id: doc.id,
            ...doc.data(),
        }));
        const preferredSeatIds = Array.isArray(order.preferredSeatIds)
            ? order.preferredSeatIds.filter((v) => typeof v === "string")
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
        const seatIds = [];
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
        for (const seatId of seatIds) {
            const ticketRef = db.collection("tickets").doc();
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
        const eventRef = db.collection("events").doc(eventId);
        transaction.update(eventRef, {
            availableSeats: admin.firestore.FieldValue.increment(-quantity),
        });
        functions.logger.info(`결제 완료 및 좌석 배정: 주문 ${orderId}, 좌석 ${seatIds.length}개`);
        return {
            success: true,
            seatBlockId: seatBlockRef.id,
            seatCount: seatIds.length,
        };
    });
});
/**
 * 연속좌석 탐색 알고리즘
 * 우선순위:
 * 1. 같은 block + floor + row에서 연속 number
 * 2. 같은 block + floor 내에서 연속 number (row 무시)
 * 3. 여러 후보 중 중앙에 가까운 좌석 우선
 */
function findConsecutiveSeats(seats, quantity, preferredSeatIds = []) {
    if (seats.length < quantity)
        return null;
    if (quantity === 1)
        return [seats[0]]; // 1장은 그냥 첫 번째
    // block + floor + row 기준 그룹핑
    const groups = new Map();
    for (const seat of seats) {
        const key = `${seat.block}-${seat.floor}-${seat.row || ""}`;
        if (!groups.has(key)) {
            groups.set(key, []);
        }
        groups.get(key).push(seat);
    }
    // 각 그룹에서 연속 좌석 찾기
    const candidates = [];
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
        const blockFloorGroups = new Map();
        for (const seat of seats) {
            const key = `${seat.block}-${seat.floor}`;
            if (!blockFloorGroups.has(key)) {
                blockFloorGroups.set(key, []);
            }
            blockFloorGroups.get(key).push(seat);
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
    if (candidates.length === 0)
        return null;
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
exports.revealSeatsForEvent = functions.https.onCall(async (request) => {
    const { eventId } = request.data;
    await assertAdmin(request.auth?.uid);
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
    // TODO: FCM 푸시 알림 발송
    // const ticketsSnapshot = await db.collection('tickets')
    //   .where('eventId', '==', eventId)
    //   .get();
    // 각 사용자에게 푸시 알림
    return {
        success: true,
        revealedBlocks: updateCount,
    };
});
// ============================================================
// 4. requestTicketCancellation - 취소/환불 처리
// ============================================================
exports.requestTicketCancellation = functions.https.onCall(async (request) => {
    const { ticketId } = request.data;
    const userId = request.auth?.uid;
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
        const ticket = ticketDoc.data();
        if (ticket.userId !== userId) {
            throw new functions.https.HttpsError("permission-denied", "권한이 없습니다");
        }
        if (ticket.status !== "issued") {
            throw new functions.https.HttpsError("failed-precondition", "취소 가능한 티켓이 아닙니다");
        }
        const eventRef = db.collection("events").doc(ticket.eventId);
        const eventDoc = await transaction.get(eventRef);
        if (!eventDoc.exists) {
            throw new functions.https.HttpsError("not-found", "공연 정보를 찾을 수 없습니다");
        }
        const event = eventDoc.data();
        const eventStartAt = toDate(event.startAt);
        if (!eventStartAt) {
            throw new functions.https.HttpsError("internal", "공연 시간이 올바르지 않습니다");
        }
        const now = new Date();
        const hoursBeforeStart = (eventStartAt.getTime() - now.getTime()) / (1000 * 60 * 60);
        if (hoursBeforeStart < REFUND_PARTIAL_HOURS) {
            throw new functions.https.HttpsError("failed-precondition", `공연 ${REFUND_PARTIAL_HOURS}시간 이내에는 취소/환불이 불가합니다`);
        }
        const refundRate = hoursBeforeStart >= REFUND_FULL_HOURS ? 1 : 0.7;
        const orderRef = db.collection("orders").doc(ticket.orderId);
        const orderDoc = await transaction.get(orderRef);
        if (!orderDoc.exists) {
            throw new functions.https.HttpsError("not-found", "주문 정보를 찾을 수 없습니다");
        }
        const order = orderDoc.data();
        const unitPrice = Number(order.unitPrice ?? 0);
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
        const orderTicketsQuery = db.collection("tickets").where("orderId", "==", ticket.orderId);
        const orderTicketsSnapshot = await transaction.get(orderTicketsQuery);
        const hasRemainingIssued = orderTicketsSnapshot.docs.some((doc) => {
            if (doc.id === ticketId)
                return false;
            return doc.data().status === "issued";
        });
        const orderUpdates = {
            canceledCount: admin.firestore.FieldValue.increment(1),
            refundedAmount: admin.firestore.FieldValue.increment(refundAmount),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (!hasRemainingIssued) {
            orderUpdates.status = refundAmount > 0 ? "refunded" : "canceled";
            orderUpdates.refundedAt = admin.firestore.FieldValue.serverTimestamp();
        }
        transaction.update(orderRef, orderUpdates);
        functions.logger.info(`티켓 취소 완료: ticket=${ticketId}, user=${userId}, rate=${refundRate}, refund=${refundAmount}`);
        return {
            success: true,
            ticketId,
            refundRate,
            refundAmount,
            policy: refundRate === 1 ? "공연 24시간 전 취소" : "공연 3시간 전 취소",
        };
    });
});
// ============================================================
// 5. issueQrToken - QR 토큰 발급 (60~120초 유효)
// ============================================================
exports.issueQrToken = functions.https.onCall(async (request) => {
    const { ticketId } = request.data;
    const userId = request.auth?.uid;
    if (!userId) {
        throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다");
    }
    // 티켓 조회
    const ticketDoc = await db.collection("tickets").doc(ticketId).get();
    if (!ticketDoc.exists) {
        throw new functions.https.HttpsError("not-found", "티켓을 찾을 수 없습니다");
    }
    const ticket = ticketDoc.data();
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
// 6. verifyAndCheckIn - 입장 검증 및 체크인
// ============================================================
exports.verifyAndCheckIn = functions.https.onCall(async (request) => {
    const { ticketId, qrToken } = request.data;
    const scannerUid = await assertStaffOrAdmin(request.auth?.uid);
    const actorStaffId = scannerUid;
    if (!ticketId || !qrToken) {
        throw new functions.https.HttpsError("invalid-argument", "잘못된 요청입니다");
    }
    // 토큰에서 실제 JWT 추출 (ticketId:token 형식)
    const tokenParts = qrToken.split(":");
    const actualToken = tokenParts.length > 1 ? tokenParts.slice(1).join(":") : qrToken;
    // JWT 검증
    let decoded;
    try {
        decoded = jwt.verify(actualToken, JWT_SECRET);
    }
    catch (error) {
        const result = error.name === "TokenExpiredError" ? "expired" : "invalidSignature";
        await logCheckin(ticketId, actorStaffId, result, error.message);
        return {
            success: false,
            result,
            message: result === "expired" ? "QR이 만료되었습니다" : "잘못된 QR입니다",
        };
    }
    // 티켓 ID 일치 확인
    if (decoded.ticketId !== ticketId) {
        await logCheckin(ticketId, actorStaffId, "invalidTicket", "티켓 ID 불일치");
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
            await logCheckin(ticketId, actorStaffId, "invalidTicket", "티켓 없음");
            return {
                success: false,
                result: "invalidTicket",
                message: "티켓을 찾을 수 없습니다",
            };
        }
        const ticket = ticketDoc.data();
        // QR 버전 확인 (재발급 시 이전 QR 무효화)
        if (decoded.qrVersion !== ticket.qrVersion) {
            await logCheckin(ticketId, actorStaffId, "invalidTicket", "QR 버전 불일치");
            return {
                success: false,
                result: "invalidTicket",
                message: "재발급된 QR입니다. 최신 QR을 사용해주세요",
            };
        }
        // 상태 확인
        if (ticket.status === "used") {
            await logCheckin(ticketId, actorStaffId, "alreadyUsed", "이미 사용됨");
            return {
                success: false,
                result: "alreadyUsed",
                message: "이미 사용된 티켓입니다",
            };
        }
        if (ticket.status === "canceled") {
            await logCheckin(ticketId, actorStaffId, "canceled", "취소된 티켓");
            return {
                success: false,
                result: "canceled",
                message: "취소된 티켓입니다",
            };
        }
        // 좌석 정보 조회
        const seatDoc = await transaction.get(db.collection("seats").doc(ticket.seatId));
        const seat = seatDoc.data();
        const seatInfo = seat
            ? `${seat.block}구역 ${seat.floor} ${seat.row || ""}열 ${seat.number}번`
            : "좌석 정보 없음";
        // 체크인 처리
        transaction.update(ticketRef, {
            status: "used",
            usedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        // 좌석 상태도 업데이트
        if (seatDoc.exists) {
            transaction.update(seatDoc.ref, { status: "used" });
        }
        // 체크인 기록
        const checkinRef = db.collection("checkins").doc();
        transaction.set(checkinRef, {
            eventId: ticket.eventId,
            ticketId,
            staffId: actorStaffId,
            result: "success",
            scannedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        functions.logger.info(`체크인 성공: 티켓 ${ticketId}, 좌석 ${seatInfo}`);
        return {
            success: true,
            result: "success",
            message: "입장 확인",
            seatInfo,
        };
    });
});
/**
 * 체크인 로그 기록 (실패 케이스용)
 */
async function logCheckin(ticketId, staffId, result, errorMessage) {
    try {
        await db.collection("checkins").add({
            ticketId,
            staffId: staffId || "unknown",
            result,
            errorMessage,
            scannedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    catch (e) {
        functions.logger.error("체크인 로그 기록 실패", e);
    }
}
// ============================================================
// 스케줄러: 좌석 자동 공개 (매 10분마다 체크)
// ============================================================
exports.scheduledRevealSeats = functions.pubsub
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
            // TODO: FCM 푸시 알림 발송
        }
    }
    return null;
});
//# sourceMappingURL=index.js.map