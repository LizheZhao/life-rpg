import Foundation

extension JournalTrends.Words {
    /// Words that never say what a month was about. Two tables per language: the function words
    /// every text has, and the filler that journals in particular are full of ("today", "feel").
    /// Matching is on the lowercased token, with curly apostrophes already straightened.
    static func isStopWord(_ token: String, language: JournalLanguage) -> Bool {
        switch language {
        case .en: englishFunctionWords.contains(token) || englishFiller.contains(token)
        case .zhHans: chineseFunctionWords.contains(token) || chineseFiller.contains(token)
        }
    }

    static let englishFunctionWords: Set<String> = [
        "a", "about", "above", "after", "again", "against", "all", "also", "am", "an", "and", "any", "are",
        "aren't", "as", "at", "be", "because", "been", "before", "being", "below", "between", "both", "but",
        "by", "can", "can't", "cannot", "could", "couldn't", "did", "didn't", "do", "does", "doesn't",
        "doing", "don't", "down", "during", "each", "few", "for", "from", "further", "had", "hadn't", "has",
        "hasn't", "have", "haven't", "having", "he", "he'd", "he'll", "he's", "her", "here", "hers",
        "herself", "him", "himself", "his", "how", "i", "i'd", "i'll", "i'm", "i've", "if", "in", "into",
        "is", "isn't", "it", "it's", "its", "itself", "let's", "me", "more", "most", "mustn't", "my",
        "myself", "no", "nor", "not", "of", "off", "on", "once", "only", "or", "other", "ought", "our",
        "ours", "ourselves", "out", "over", "own", "same", "shan't", "she", "she'd", "she'll", "she's",
        "should", "shouldn't", "so", "some", "such", "than", "that", "that's", "the", "their", "theirs",
        "them", "themselves", "then", "there", "there's", "these", "they", "they'd", "they'll", "they're",
        "they've", "this", "those", "through", "to", "too", "under", "until", "up", "us", "very", "was",
        "wasn't", "we", "we'd", "we'll", "we're", "we've", "were", "weren't", "what", "what's", "when",
        "where", "which", "while", "who", "whom", "why", "will", "with", "won't", "would", "wouldn't",
        "you", "you'd", "you'll", "you're", "you've", "your", "yours", "yourself", "yourselves",
    ]

    static let englishFiller: Set<String> = [
        "today", "tonight", "yesterday", "tomorrow", "feel", "feels", "felt", "feeling", "like", "liked",
        "just", "got", "get", "gets", "getting", "go", "goes", "going", "went", "gone", "make", "made",
        "makes", "think", "thought", "know", "knew", "want", "wanted", "need", "needed", "really",
        "pretty", "quite", "much", "many", "lot", "lots", "bit", "little", "kind", "sort", "still", "even",
        "maybe", "probably", "actually", "though", "thing", "things", "something", "anything", "everything",
        "nothing", "one", "day", "days", "time", "times", "back", "way", "well", "good", "okay", "fine",
        "grateful", "now", "then", "again", "always", "never", "sometimes", "morning", "evening",
        "night", "ended", "started", "start", "came", "come", "take", "took", "said", "say",
    ]

    /// Single characters are real words in Chinese ("猫", "雨"), so the function-word table has to
    /// list the single-character particles and pronouns that the tokenizer splits off.
    static let chineseFunctionWords: Set<String> = [
        "的", "了", "是", "我", "你", "他", "她", "它", "们", "在", "有", "和", "就", "都", "也", "很", "不",
        "到", "说", "要", "去", "会", "着", "没", "看", "这", "那", "个", "把", "被", "让", "给", "对", "从",
        "向", "跟", "与", "及", "或", "但", "而", "且", "还", "又", "再", "才", "只", "更", "最", "太", "好",
        "小", "大", "多", "少", "上", "下", "中", "里", "来", "过", "吗", "呢", "吧", "啊", "呀", "哦", "嗯",
        "啦", "么", "什", "怎", "为", "因", "所", "以", "然", "后", "一", "二", "三", "四", "五", "六", "七",
        "八", "九", "十", "等", "地", "得", "之", "其", "已", "将", "能", "可", "想", "做", "用", "同", "还是",
        "我们", "你们", "他们", "她们", "它们", "自己", "什么", "怎么", "因为", "所以", "但是", "然后", "已经",
        "可以", "如果", "虽然", "或者", "以及", "一个", "这个", "那个", "这样", "那样", "这些", "那些", "一些",
        "一下", "一点", "有点", "有些", "还有", "没有", "不是", "就是", "也是", "都是", "时候", "为了",
    ]

    static let chineseFiller: Set<String> = [
        "今天", "昨天", "明天", "今晚", "早上", "晚上", "下午", "中午", "觉得", "感觉", "真的", "其实",
        "非常", "比较", "特别", "一直", "应该", "可能", "需要", "想要", "开始", "最后", "终于", "东西",
        "事情", "现在", "后来", "之后", "之前", "有点", "感到",
    ]
}
