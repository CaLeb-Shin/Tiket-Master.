"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.NaverTicketLogicError = void 0;
exports.parseNaverOrderCreateInput = parseNaverOrderCreateInput;
exports.evaluateCancelOrderStatus = evaluateCancelOrderStatus;
exports.buildMobileTicketPublicPayload = buildMobileTicketPublicPayload;
class NaverTicketLogicError extends Error {
    constructor(code, message) {
        super(message);
        this.code = code;
        this.name = "NaverTicketLogicError";
    }
}
exports.NaverTicketLogicError = NaverTicketLogicError;
function normalizeMobileTicketStatus(value) {
    if (value === "used") {
        return "used";
    }
    if (value === "canceled" || value === "cancelled") {
        return "cancelled";
    }
    return "active";
}
function toDate(value) {
    if (!value)
        return null;
    if (typeof value?.toDate === "function") {
        const dated = value.toDate();
        return dated instanceof Date && !Number.isNaN(dated.getTime()) ? dated : null;
    }
    if (value instanceof Date) {
        return Number.isNaN(value.getTime()) ? null : value;
    }
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
}
function isEventRevealed(event, now = new Date()) {
    const revealAt = toDate(event?.revealAt);
    return revealAt == null || now >= revealAt;
}
function buildPublicTicketDisplayState(status, options) {
    if (status === "cancelled") {
        return { code: "cancelled", label: "취소됨" };
    }
    if (status === "used") {
        return { code: "used", label: "사용 완료" };
    }
    if (!options.isRevealed) {
        return { code: "beforeReveal", label: "공개 전" };
    }
    if (options.isIntermissionCheckedIn) {
        return { code: "intermissionCheckedIn", label: "인터미션 완료" };
    }
    if (options.isCheckedIn) {
        return { code: "entryCheckedIn", label: "1부 입장완료" };
    }
    return { code: "active", label: "사용 가능" };
}
function parseNaverOrderCreateInput(raw) {
    const eventId = typeof raw?.eventId === "string" ? raw.eventId.trim() : "";
    const naverOrderId = typeof raw?.naverOrderId === "string" ? raw.naverOrderId.trim() : "";
    const buyerName = typeof raw?.buyerName === "string" ? raw.buyerName.trim() : "";
    const buyerPhone = typeof raw?.buyerPhone === "string" ? raw.buyerPhone.trim() : "";
    const seatGrade = typeof raw?.seatGrade === "string" ? raw.seatGrade.trim() : "";
    const quantity = Number(raw?.quantity);
    if (!eventId || !naverOrderId || !buyerName || !buyerPhone || !seatGrade || !Number.isInteger(quantity) || quantity <= 0) {
        throw new NaverTicketLogicError("invalid-argument", "필수 필드가 누락되었거나 수량이 올바르지 않습니다");
    }
    return {
        eventId,
        naverOrderId,
        buyerName,
        buyerPhone,
        productName: typeof raw?.productName === "string" ? raw.productName.trim() : "",
        seatGrade,
        quantity,
        orderDate: typeof raw?.orderDate === "string" ? raw.orderDate : undefined,
        memo: typeof raw?.memo === "string" && raw.memo.trim() !== "" ? raw.memo.trim() : null,
        dryRun: raw?.dryRun === true,
        skipSms: raw?.skipSms === true,
    };
}
function evaluateCancelOrderStatus(status, allowAlreadyCancelled = false) {
    if (status === "confirmed") {
        return { alreadyCancelled: false };
    }
    if (allowAlreadyCancelled) {
        return {
            alreadyCancelled: true,
            message: "이미 취소된 주문",
        };
    }
    throw new NaverTicketLogicError("failed-precondition", "이미 취소된 주문입니다");
}
function buildPublicTicketDto(params) {
    const ticketStatus = normalizeMobileTicketStatus(params.ticket.status);
    const ticketIsCheckedIn = !!params.ticket.entryCheckedInAt;
    const ticketIsIntermissionCheckedIn = !!params.ticket.intermissionCheckedInAt;
    const ticketDisplayState = buildPublicTicketDisplayState(ticketStatus, {
        isCheckedIn: ticketIsCheckedIn,
        isIntermissionCheckedIn: ticketIsIntermissionCheckedIn,
        isRevealed: params.isRevealed,
    });
    return {
        id: params.ticketId,
        eventId: params.ticket.eventId,
        naverOrderId: params.ticket.naverOrderId || null,
        accessToken: params.ticket.accessToken || null,
        seatGrade: params.ticket.seatGrade,
        seatInfo: params.isRevealed ? params.ticket.seatInfo : null,
        seatNumber: params.isRevealed ? params.ticket.seatNumber : null,
        buyerName: params.ticket.buyerName,
        buyerPhone: params.ticket.buyerPhone || null,
        buyerPhoneLast4: params.ticket.buyerPhone && params.ticket.buyerPhone.length >= 4
            ? params.ticket.buyerPhone.slice(-4)
            : null,
        recipientName: params.ticket.recipientName || null,
        status: ticketStatus,
        entryNumber: params.ticket.entryNumber,
        orderIndex: params.ticket.orderIndex || null,
        totalInOrder: params.ticket.totalInOrder || null,
        qrVersion: params.ticket.qrVersion || 1,
        isCheckedIn: ticketIsCheckedIn,
        isIntermissionCheckedIn: ticketIsIntermissionCheckedIn,
        lastCheckInStage: params.ticket.lastCheckInStage || null,
        displayStatus: ticketDisplayState.code,
        displayStatusLabel: ticketDisplayState.label,
    };
}
function buildMobileTicketPublicPayload(params) {
    const isRevealed = isEventRevealed(params.event, params.now);
    const siblings = (params.siblingDocs || [])
        .map((sibling) => buildPublicTicketDto({
        ticketId: sibling.id,
        ticket: sibling.data,
        isRevealed,
    }))
        .sort((a, b) => (a.orderIndex || a.entryNumber || 0) - (b.orderIndex || b.entryNumber || 0));
    return {
        success: true,
        ticket: buildPublicTicketDto({
            ticketId: params.ticketId,
            ticket: params.ticket,
            isRevealed,
        }),
        event: params.event
            ? {
                title: params.event.title,
                imageUrl: params.event.imageUrl || null,
                startAt: params.event.startAt,
                venueName: params.event.venueName || "",
                venueAddress: params.event.venueAddress || "",
                revealAt: params.event.revealAt,
                naverProductUrl: params.event.naverProductUrl || null,
                pamphletUrls: params.event.pamphletUrls || [],
                eventStatus: params.event.eventStatus || "active",
            }
            : null,
        isRevealed,
        siblings,
    };
}
//# sourceMappingURL=naver_ticket_logic.js.map