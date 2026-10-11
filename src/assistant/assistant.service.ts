/** Grounded assistant: source-aware retrieval with optional model synthesis. */
import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { SearchService } from '../search/search.service';
import {
  AssistantEvidence, createSystemPrompt, enforceSafetyFloor, evidenceFromSearch,
  parseModelAnswer, redactSecrets, retrievalFallback, validateQuestion,
} from './assistant.logic';
import { evidenceMatchesQuestion, financialEmergencyFirstAid, otpFirstAid, readRecentQuestions, routeScope, scopeReply, scamClarification, shouldClarifyScam } from './assistant.triage';

@Injectable()
export class AssistantService {
  private readonly logger = new Logger(AssistantService.name);
  constructor(private readonly search: SearchService) {}

  async ask(body: Record<string, unknown>, staff: boolean) {
    const question = validateQuestion(body.question);
    const domain = body.domain === undefined ? 'ALL' : body.domain;
    if (!['ALL', 'LEGAL', 'ADMIN', 'SCAM'].includes(String(domain)))
      throw new Error('Lĩnh vực không hợp lệ.');
    const safeQuestion = redactSecrets(question);
    const recent = readRecentQuestions(body.history).map(redactSecrets);
    const scope = routeScope(safeQuestion, recent);
    // Never depend on SQL Server or a live LLM to provide time-critical OTP first aid.
    const otpSafety = financialEmergencyFirstAid(safeQuestion, recent) || otpFirstAid(safeQuestion, recent);
    if (otpSafety) return {
      mode: staff ? 'STAFF_DRAFT_PREVIEW' : 'PUBLISHED_ONLY', status: 'SAFETY_GUIDANCE',
      modelActive: false, intent: 'SAFETY', urgentSafety: true,
      missingInformation: otpSafety.conditions, evidence: [], links: [], answer: otpSafety,
      disclaimer: 'Hướng dẫn bảo vệ tài khoản ban đầu; không phải kết luận rằng cá nhân hoặc tổ chức đã lừa đảo.',
    };
    if (scope !== 'IN_SCOPE') return {
      mode: staff ? 'STAFF_DRAFT_PREVIEW' : 'PUBLISHED_ONLY',
      status: scope === 'OUT_OF_SCOPE' ? 'OUT_OF_SCOPE' : 'NEEDS_CLARIFICATION',
      modelActive: false, intent: 'GENERAL', urgentSafety: false,
      missingInformation: [], evidence: [], links: [], answer: scopeReply(scope),
      disclaimer: 'Trợ lý chỉ hỗ trợ pháp luật, quyền lợi, thủ tục hành chính và phòng tránh lừa đảo.',
    };
    const clarification = shouldClarifyScam(safeQuestion, recent);
    if (clarification) {
      return {
        mode: staff ? 'STAFF_DRAFT_PREVIEW' : 'PUBLISHED_ONLY',
        status: 'NEEDS_CLARIFICATION', modelActive: false, intent: 'SAFETY',
        urgentSafety: true, missingInformation: [], evidence: [], links: [],
        answer: scamClarification(safeQuestion, clarification, staff),
        disclaimer: 'Đây là hướng dẫn xử lý ban đầu; không suy đoán thủ đoạn hay kết luận pháp lý.',
      };
    }
    const result = await this.search.search({ q: safeQuestion, domain, limit: '5' }, staff);
    const all = [...result.results, ...result.related];
    const excerpts = await this.search.excerptsForAssistant(all, staff);
    const evidence = evidenceFromSearch(result, excerpts, staff)
      .filter(e => evidenceMatchesQuestion(safeQuestion, e));
    const fallback = retrievalFallback(safeQuestion, evidence, staff);
    const base = {
      mode: staff ? 'STAFF_DRAFT_PREVIEW' : 'PUBLISHED_ONLY', retrieval: result.retrieval,
      intent: result.intent, urgentSafety: result.urgentSafety, missingInformation: result.missingInformation,
      evidence: evidence.map(({ excerpt, ...rest }) => rest), links: result.links.slice(0, 12),
      disclaimer: staff
        ? 'CHỈ DÙNG NỘI BỘ: bản nháp và nguồn chưa xác minh; không phải tư vấn pháp lý hoặc kết luận chính thức.'
        : 'Trợ lý thông tin không thay thế cơ quan có thẩm quyền. Chỉ dùng nội dung đã công bố có nguồn xác minh.',
    };
    // Lack of published evidence is NOT a reason to suppress the real model.
    // The model may offer non-authoritative general guidance but no legal specifics or fake citations.
    // Local Ollama needs no paid API key; the token 'ollama' is ignored by localhost.
    const local = process.env.AI_PROVIDER?.trim().toLowerCase() === 'ollama';
    const key = local ? 'ollama' : process.env.AI_API_KEY?.trim();
    const model = process.env.AI_MODEL?.trim();
    const draftsEnabled = process.env.AI_ALLOW_STAFF_DRAFTS === 'true';
    if (!key || !model || (staff && !draftsEnabled)) {
      return { ...base, status: 'RETRIEVAL_ONLY', answer: fallback, modelActive: false,
        notice: staff && !draftsEnabled ? 'AI chưa được phép sử dụng bản nháp; bật AI_ALLOW_STAFF_DRAFTS chỉ khi thử nghiệm nội bộ.'
          : 'Chưa cấu hình mô hình AI. Hãy chạy tools/ai/start-gds.ps1; hiện chỉ tra cứu dữ liệu.' };
    }
    try {
      const raw = await this.generate(safeQuestion, recent, evidence, staff, key, model);
      let usedEvidence = evidence;
      let parsedBase = parseModelAnswer(raw, evidence, staff);
      // Small local models sometimes omit citation IDs. Instead of serving an
      // identical canned fallback for every question, ask for a separate general
      // answer WITHOUT evidence, and never present it as source-backed.
      if (!parsedBase && evidence.length) {
        const generalRaw = await this.generate(safeQuestion, recent, [], staff, key, model);
        parsedBase = parseModelAnswer(generalRaw, [], staff);
        usedEvidence = [];
      }
      const parsed = parsedBase ? enforceSafetyFloor(safeQuestion, parsedBase) : null;
      if (!parsed) return { ...base, status: 'PROVIDER_UNAVAILABLE', answer: fallback, modelActive: false,
        notice: 'Mô hình không trả về JSON hợp lệ hoặc không dẫn nguồn phù hợp; đang hiển thị kết quả tra cứu dự phòng.' };
      return { ...base, status: 'AI_GENERATED', answer: parsed, modelActive: true,
        evidence: usedEvidence.length ? base.evidence : [], links: usedEvidence.length ? base.links : [],
        notice: usedEvidence.length
          ? 'AI tổng hợp từ tài liệu liên quan; kiểm tra nguồn và thời điểm áp dụng.'
          : 'AI trả lời hướng dẫn chung; kho dữ liệu hiện chưa có nguồn đã kiểm chứng cho câu hỏi này.' };
    } catch (error: unknown) {
      const reason = error instanceof Error ? error.name : 'UnknownError';
      this.logger.warn('Provider unavailable (' + reason + '); fallback to retrieval-only answer.');
      return { ...base, status: 'PROVIDER_UNAVAILABLE', answer: fallback, modelActive: false,
        notice: 'Dịch vụ AI hiện không phản hồi; hệ thống vẫn hiển thị thông tin tìm được và không tự tạo kết luận.' };
    }
  }

  private async generate(question: string, history: string[], evidence: AssistantEvidence[], staff: boolean, key: string, model: string): Promise<string> {
    const base = process.env.AI_BASE_URL?.trim() ||
      (process.env.AI_PROVIDER?.toLowerCase() === 'ollama' ? 'http://127.0.0.1:11434/v1' : 'https://api.openai.com/v1');
    const url = new URL(base.replace(/\/+$/, '') + '/chat/completions');
    if (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['127.0.0.1', 'localhost', '::1'].includes(url.hostname)))
      throw new ServiceUnavailableException('AI_BASE_URL không hợp lệ.');
    const context = evidence.map(e => ({ id: e.id, domain: e.domain, businessCode: e.businessCode, title: e.title,
      summary: e.summary, excerpt: e.excerpt, sourceTitle: e.sourceTitle, sourceUrl: e.sourceUrl,
      sourceStatus: e.sourceStatus, editorialStatus: e.editorialStatus }));
    const payload = { model, messages: [
      { role: 'system', content: createSystemPrompt(staff) },
      { role: 'user', content: JSON.stringify({ question, recentUserMessages: history.slice(-3), mode: staff ? 'DRAFT_INTERNAL' : 'PUBLISHED_ONLY', evidence: context }) },
    ], temperature: 0.35, max_tokens: 850, response_format: { type: 'json_object' } };
    const controller = new AbortController();
    // Local CPU inference can take longer than a remote model.
    const timeout = setTimeout(() => controller.abort(), process.env.AI_PROVIDER?.toLowerCase() === 'ollama' ? 180000 : 30000);
    try {
      const response = await fetch(url.toString(), { method: 'POST', signal: controller.signal,
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + key }, body: JSON.stringify(payload) });
      if (!response.ok) throw new Error('AI provider HTTP error');
      const json: unknown = await response.json();
      const content = (json as { choices?: Array<{ message?: { content?: unknown } }> })?.choices?.[0]?.message?.content;
      if (typeof content !== 'string' || content.length > 14000) throw new Error('Malformed provider response');
      return content;
    } finally { clearTimeout(timeout); }
  }
}
