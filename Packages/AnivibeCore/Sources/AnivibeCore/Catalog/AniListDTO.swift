import Foundation

// DTO для ответов AniList GraphQL (https://docs.anilist.co/reference/).

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLErrorDTO]?
}

struct GraphQLErrorDTO: Decodable {
    let message: String
    let status: Int?
}

struct PageInfoDTO: Decodable {
    let currentPage: Int?
    let hasNextPage: Bool?
}

struct MediaPageDTO: Decodable {
    let pageInfo: PageInfoDTO?
    let media: [MediaDTO?]?
}

struct SearchResponseDTO: Decodable { let Page: MediaPageDTO? }
struct DetailsResponseDTO: Decodable { let Media: MediaDTO? }
struct GenresResponseDTO: Decodable { let GenreCollection: [String]? }
struct HomeResponseDTO: Decodable {
    let popular: MediaPageDTO?
    let seasonal: MediaPageDTO?
    let trending: MediaPageDTO?
    let recent: MediaPageDTO?
}

struct MediaDTO: Decodable {
    struct Title: Decodable { let romaji: String?; let english: String?; let native: String? }
    struct Cover: Decodable { let large: String?; let extraLarge: String?; let color: String? }
    struct FuzzyDate: Decodable { let year: Int? }
    struct NextAiring: Decodable { let episode: Int? }
    struct RelationEdge: Decodable { let relationType: String?; let node: MediaDTO? }
    struct Relations: Decodable { let edges: [RelationEdge?]? }
    struct StreamingEpisode: Decodable { let title: String?; let thumbnail: String?; let url: String?; let site: String? }
    struct ExternalLinkDTO: Decodable { let site: String?; let url: String?; let type: String?; let language: String? }
    struct StudioNode: Decodable { let name: String? }
    struct Studios: Decodable { let nodes: [StudioNode?]? }
    struct RecNode: Decodable { let mediaRecommendation: MediaDTO? }
    struct Recs: Decodable { let nodes: [RecNode?]? }

    let id: Int
    let title: Title?
    let synonyms: [String?]?
    let description: String?
    let coverImage: Cover?
    let bannerImage: String?
    let seasonYear: Int?
    let season: String?
    let startDate: FuzzyDate?
    let genres: [String?]?
    let status: String?
    let format: String?
    let averageScore: Int?
    let episodes: Int?
    let duration: Int?
    let nextAiringEpisode: NextAiring?
    let isAdult: Bool?
    let relations: Relations?
    let streamingEpisodes: [StreamingEpisode?]?
    let externalLinks: [ExternalLinkDTO?]?
    let studios: Studios?
    let recommendations: Recs?

    var model: Anime {
        Anime(
            id: id,
            title: AnimeTitle(romaji: title?.romaji, english: title?.english, native: title?.native),
            synonyms: (synonyms ?? []).compactMap { $0?.nilIfBlank },
            synopsis: description.map(HTMLText.plainText).flatMap { $0.nilIfBlank },
            coverURL: (coverImage?.extraLarge ?? coverImage?.large).flatMap(Self.httpsURL),
            bannerURL: bannerImage.flatMap(Self.httpsURL),
            coverColorHex: coverImage?.color,
            year: seasonYear ?? startDate?.year,
            season: season.flatMap(AnimeSeason.init(rawValue:)),
            genres: (genres ?? []).compactMap { $0 },
            status: AiringStatus(apiValue: status),
            format: format.flatMap(AnimeFormat.init(rawValue:)),
            averageScore: averageScore,
            episodeCount: episodes,
            episodeDurationMinutes: duration,
            nextAiringEpisode: nextAiringEpisode?.episode
        )
    }

    var detailsModel: AnimeDetails {
        let rels: [RelatedAnime] = (relations?.edges ?? []).compactMap { edge in
            guard let edge, let node = edge.node, node.isAdult != true else { return nil }
            return RelatedAnime(relation: RelationType(rawValue: edge.relationType ?? "") ?? .other, anime: node.model)
        }
        let streams: [StreamingEpisodeInfo] = (streamingEpisodes ?? []).compactMap { ep in
            guard let ep, let t = ep.title?.nilIfBlank else { return nil }
            return StreamingEpisodeInfo(title: t, thumbnailURL: ep.thumbnail.flatMap(Self.httpsURL),
                                        url: ep.url.flatMap(Self.httpsURL), site: ep.site)
        }
        let links: [ExternalLink] = (externalLinks ?? []).compactMap { link in
            guard let link, link.type == "STREAMING", let site = link.site, let url = link.url.flatMap(Self.httpsURL) else { return nil }
            return ExternalLink(site: site, url: url, language: link.language)
        }
        return AnimeDetails(
            anime: model,
            relations: rels,
            streamingEpisodes: streams,
            externalStreamingLinks: links,
            studios: (studios?.nodes ?? []).compactMap { $0?.name },
            recommendations: (recommendations?.nodes ?? []).compactMap { $0?.mediaRecommendation }.filter { $0.isAdult != true }.map(\.model)
        )
    }

    /// Принимаем только https-ссылки (ATS) и безопасно повышаем http→https для CDN каталога.
    static func httpsURL(_ s: String) -> URL? {
        guard var comps = URLComponents(string: s) else { return nil }
        if comps.scheme == "http" { comps.scheme = "https" }
        guard comps.scheme == "https", comps.host != nil else { return nil }
        return comps.url
    }
}

/// Минимальное JSON-значение для переменных GraphQL.
enum JSONValue: Encodable, Hashable {
    case string(String), int(Int), bool(Bool), array([JSONValue]), null

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }
}

struct GraphQLRequestBody: Encodable {
    let query: String
    let variables: [String: JSONValue]
}
