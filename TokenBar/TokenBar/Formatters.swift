import Foundation

enum TokenFormatter {
    static func format(_ count: Int) -> String {
        if count >= 1_000_000 {
            let millions = Double(count) / 1_000_000
            return String(format: "%.1fM", millions)
        } else if count >= 1_000 {
            let thousands = Double(count) / 1_000
            return String(format: "%.1fK", thousands)
        }
        return "\(count)"
    }

    static func formatWithCommas(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    static func formatCost(_ dollars: Double) -> String {
        if dollars >= 1.0 {
            return String(format: "$%.2f", dollars)
        } else {
            return String(format: "$%.3f", dollars)
        }
    }

    static let modelNames: [String: String] = [
        // Claude
        "claude-opus-4-6": "Opus 4.6",
        "claude-opus-4-5-20251101": "Opus 4.5",
        "claude-sonnet-4-5-20250929": "Sonnet 4.5",
        "claude-haiku-4-5-20251001": "Haiku 4.5",
        // OpenCode / Ollama
        "qwen3:8b": "Qwen3 8B",
        "qwen2.5:14b": "Qwen2.5 14B",
        "llama3.1:8b": "Llama 3.1 8B",
        "deepseek-coder-v2:16b": "DeepSeek V2 16B",
        "devstral-small-2": "Devstral Small",
        "nomic-embed-text": "Nomic Embed",
        "kimi-k2-turbo-preview": "Kimi K2 Turbo",
        "kimi-k2.5": "Kimi K2.5",
    ]

    static func friendlyModelName(_ id: String) -> String {
        modelNames[id] ?? id
    }

    // Per-million-token pricing
    struct ModelPricing {
        let inputPerMillion: Double
        let outputPerMillion: Double
        let cacheReadPerMillion: Double
        let cacheWritePerMillion: Double
    }

    static let pricing: [String: ModelPricing] = [
        // Claude (Anthropic API)
        "claude-opus-4-6": ModelPricing(
            inputPerMillion: 15.0, outputPerMillion: 75.0,
            cacheReadPerMillion: 1.5, cacheWritePerMillion: 3.75
        ),
        "claude-opus-4-5-20251101": ModelPricing(
            inputPerMillion: 15.0, outputPerMillion: 75.0,
            cacheReadPerMillion: 1.5, cacheWritePerMillion: 3.75
        ),
        "claude-sonnet-4-5-20250929": ModelPricing(
            inputPerMillion: 3.0, outputPerMillion: 15.0,
            cacheReadPerMillion: 0.3, cacheWritePerMillion: 0.75
        ),
        "claude-haiku-4-5-20251001": ModelPricing(
            inputPerMillion: 0.80, outputPerMillion: 4.0,
            cacheReadPerMillion: 0.08, cacheWritePerMillion: 0.2
        ),
        // Kimi (Moonshot AI API)
        "kimi-k2-turbo-preview": ModelPricing(
            inputPerMillion: 1.15, outputPerMillion: 8.0,
            cacheReadPerMillion: 0.15, cacheWritePerMillion: 0.0
        ),
        "kimi-k2.5": ModelPricing(
            inputPerMillion: 0.60, outputPerMillion: 3.0,
            cacheReadPerMillion: 0.10, cacheWritePerMillion: 0.0
        ),
    ]

    static func estimateCost(model: String, usage: ModelUsage) -> Double {
        guard let price = pricing[model] else { return 0 }
        let input = Double(usage.inputTokens) / 1_000_000 * price.inputPerMillion
        let output = Double(usage.outputTokens) / 1_000_000 * price.outputPerMillion
        let cacheRead = Double(usage.cacheReadInputTokens) / 1_000_000 * price.cacheReadPerMillion
        let cacheWrite = Double(usage.cacheCreationInputTokens) / 1_000_000 * price.cacheWritePerMillion
        return input + output + cacheRead + cacheWrite
    }

    static func estimateCostOpenCode(model: String, usage: OpenCodeModelUsage) -> Double {
        guard let price = pricing[model] else { return 0 }
        let input = Double(usage.input) / 1_000_000 * price.inputPerMillion
        let output = Double(usage.output) / 1_000_000 * price.outputPerMillion
        let cacheRead = Double(usage.cacheRead) / 1_000_000 * price.cacheReadPerMillion
        return input + output + cacheRead
    }

    static func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "12am" }
        if hour < 12 { return "\(hour)am" }
        if hour == 12 { return "12pm" }
        return "\(hour - 12)pm"
    }
}
