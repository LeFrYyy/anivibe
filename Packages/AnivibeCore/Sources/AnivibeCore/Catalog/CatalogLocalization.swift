import Foundation
public enum CatalogLocalization {
    public static func genre(_ original: String) -> String {
        ["Action":"Экшен", "Adventure":"Приключения", "Comedy":"Комедия", "Drama":"Драма", "Ecchi":"Этти",
         "Fantasy":"Фэнтези", "Horror":"Ужасы", "Mahou Shoujo":"Девочки-волшебницы", "Mecha":"Меха", "Music":"Музыка",
         "Mystery":"Детектив", "Psychological":"Психологическое", "Romance":"Романтика", "Sci-Fi":"Фантастика",
         "Slice of Life":"Повседневность", "Sports":"Спорт", "Supernatural":"Сверхъестественное", "Thriller":"Триллер"] [original] ?? original
    }
}
