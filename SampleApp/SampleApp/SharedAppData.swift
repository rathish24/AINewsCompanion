import Foundation

// MARK: - Shared article model and list (used by both App1 and App2 tabs)

struct SkyArticle: Identifiable {
    let id: String
    let category: String
    let title: String
    let url: URL
}

let skyArticleList: [SkyArticle] = [
    SkyArticle(
        id: "home-1",
        category: "Home",
        title: "War us and israles",
        url: URL(string: "https://news.sky.com/story/iran-war-the-strategy-behind-the-us-and-israels-strikes-13516343")!
    ),
    SkyArticle(
        id: "world-1",
        category: "World",
        title: "Is Britain really off the booze for good?",
        url: URL(string: "https://news.sky.com/story/money-live-tips-personal-finance-consumer-sky-news-latest-13040934")!
    ),
    SkyArticle(
        id: "sports-1",
        category: "Sports",
        title: "Australian GP Qualifying: Lando Norris claims pole, Hamilton eighth on Ferrari debut",
        url: URL(string: "https://www.skysports.com/f1/news/12433/13328870/australian-gp-qualifying-lando-norris-claims-pole-position-with-lewis-hamilton-only-eighth-on-ferrari-debut")!
    )
]
