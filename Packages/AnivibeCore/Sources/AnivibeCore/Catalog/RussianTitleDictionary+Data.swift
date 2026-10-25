import Foundation

// Сгенерировано scripts/generate_russian_titles.py по публичным данным Shikimori (топ по популярности)
// и ручному списку разговорных названий. Формат строки: malID<TAB>русское<TAB>ромадзи<TAB>english|…<TAB>алиас|…
// Запрещённые в данных символы: табуляция и вертикальная черта заменяются при генерации.
extension RussianTitleDictionary {
    static let rawData = """
1	Ковбой Бибоп	Cowboy Bebop	Cowboy Bebop	Ковбой Бибоп 1998
5	Ковбой Бибоп: Достучаться до небес	Cowboy Bebop: Tengoku no Tobira	Cowboy Bebop: The Movie	Cowboy Bebop: Knockin' on Heaven's Door
6	Триган	Trigun	Trigun	Тригун
18	Инициал Ди: Стадия четвёртая	Initial D Fourth Stage		Initial D 4th Stage|Инициал Ди|Инишиал Ди
19	Монстр	Monster	Monster	Монстр 2004
20	Наруто	Naruto	Naruto	NARUTO|Наруто 1 сезон
21	Ван-Пис	One Piece	One Piece	Большой куш|Одним куском|Ван Пис|Уан Пис|Одно целое|Ванпис
22	Принц тенниса	Tennis no Oujisama	The Prince of Tennis	TeniPuri|PoT
24	Школьный переполох	School Rumble	School Rumble	Скул Рамбл
30	Евангелион нового поколения	Shinseiki Evangelion	Neon Genesis Evangelion	NGE|Evangelion (1995)|Евангелион|Ева|Евангелион 1995
32	Евангелион нового поколения: Конец Евангелиона	Shinseiki Evangelion Movie: Air/Magokoro wo, Kimi ni	Neon Genesis Evangelion: The End of Evangelion	Shinseiki Evangelion Gekijouban: The End of Evangelion|EoE|Конец Евангелиона|Евангелион: Конец
33	Берсерк	Kenpuu Denki Berserk	Berserk	Berserk: The Chronicles of Wind Blades|Sword-Wind Chronicle Berserk|Kenpu Denki Beruseruku|Берсерк 1997
43	Призрак в доспехах	Koukaku Kidoutai	Ghost in the Shell	Дух в стальной плоти|Дух в стальной оболочке
45	Бродяга Кэнсин	Rurouni Kenshin: Meiji Kenkaku Romantan	Rurouni Kenshin	Samurai X|Бродяга Кеншин|Самурай Икс|Самурай X
47	Акира	Akira	Akira	
121	Стальной алхимик	Fullmetal Alchemist	Fullmetal Alchemist	Цельнометаллический алхимик|Hagane no Renkinjutsushi|FMA|Full Metal Alchemist|Стальной алхимик 2003
136	Охотник х Охотник	Hunter x Hunter	Hunter x Hunter	HxH|Хантер х Хантер 1999|Охотник х Охотник 1999
164	Принцесса Мононоке	Mononoke Hime	Princess Mononoke	Принцесса Мононокэ
170	Слэм-данк	Slam Dunk	Slam Dunk	Коронный бросок|Слэм данк|Слем данк
199	Унесённые призраками	Sen to Chihiro no Kamikakushi	Spirited Away	Sen and Chihiro's Spiriting Away|Унесенные призраками|Тихиро
205	Самурай Чамплу	Samurai Champloo	Samurai Champloo	Samurai Chanpuru|Самурай Тямпуру|Самурай Чамплю
223	Драконий жемчуг	Dragon Ball	Dragon Ball	Dragonball|DB|Жемчуг дракона|Драгон Болл|Драгонболл
225	Драконий жемчуг БП	Dragon Ball GT	Dragon Ball GT	Драконий жемчуг: Большое путешествие|Dragonball GT|DBGT|Dragon Ball Grand Tour
226	Эльфийская песнь	Elfen Lied	Elfen Lied	Elfen Song|Elfic Song|Elf Song|Эльфен Лид|Эльфийская песня
227	Фури-кури	FLCL	FLCL	Fooly Cooly|Furi Kuri|Фури Кури|ФЛКЛ
228	Адская девочка	Jigoku Shoujo	Hell Girl	Девочка из ада|Jigoku Shojo
232	Сакура — собирательница карт	Cardcaptor Sakura	Cardcaptor Sakura	CCS|Cardcaptors|Card Captor Sakura|Сакура собирательница карт|Сакура ловец карт
245	Крутой учитель Онидзука	Great Teacher Onizuka	Great Teacher Onizuka	Великий учитель Онидзука|GTO|Крутой учитель Онизука|ГТО
249	Инуяся	InuYasha	InuYasha	Inu Yasha|Инуяша|Инуяша 1 сезон
263	Первый шаг	Hajime no Ippo	Fighting Spirit	The First Step|Hajime no Ippo: The Fighting|Хадзиме но Иппо|Иппо
269	Блич	Bleach	Bleach	
270	Хеллсинг: Война с нечистью	Hellsing	Hellsing	Хеллсинг|Хелсинг|Хеллсинг 2001
339	Эксперименты Лэйн	Serial Experiments Lain	Serial Experiments Lain	Лэйн
356	Судьба/Ночь схватки	Fate/stay night	Fate/stay night	Судьба: Ночь Прибытия|Судьба: Ночь схватки|Фейт Стей Найт
392	Отчёт о буйстве духов	Yuu☆Yuu☆Hakusho	Yu Yu Hakusho: Ghost Files	Yu Yu Hakusho|Ghost Fighter|Poltergeist Report|YuYu Hakusho|Отчет о буйстве духов|Ю Ю Хакусё|Ю Ю Хакушо
416	Порко Россо	Kurenai no Buta	Porco Rosso	The Scarlet Pig
430	Стальной алхимик: Завоеватель Шамбалы	Fullmetal Alchemist: The Conqueror of Shamballa	Fullmetal Alchemist: The Movie - Conqueror of Shamballa	Цельнометаллический алхимик: Завоеватель Шамбалы|Gekijyouban Hagane no Renkinjutsushi - Shanbara wo Yuku Mono|Fullmetal Alchemist the Movie: Conqueror of Shamballa|FMA Movie
431	Ходячий замок	Howl no Ugoku Shiro	Howl's Moving Castle	Ходячий замок Хаула|Бродячий замок Хоула
437	Идеальная грусть	Perfect Blue	Perfect Blue	Идеальная синева|Истинная грусть|Перфект Блю
442	Наруто 1: Книга искусств ниндзя Снежной принцессы	Naruto Movie 1: Dai Katsugeki!! Yuki Hime Ninpouchou Dattebayo!	Naruto the Movie 1: Ninja Clash in the Land of Snow	Наруто 1: Великая Миссия! Защитить принцессу Страны снега|Наруто 1: Ниндзя в Стране снега|Naruto: Daikatsugeki! Yukihime Ninpocho Dattebayo!|Naruto: It's the Snow Princess' Ninja Art Book!
457	Мастер муси	Mushishi	Mushi-Shi	Знаток муси|Мастер Муси|Мусиси|Мушиши
467	Призрак в доспехах: Синдром одиночки	Koukaku Kidoutai: Stand Alone Complex	Ghost in the Shell: Stand Alone Complex	Ghost in the Shell SAC|Призрак в доспехах|Призрак в доспехах 1995
512	Ведьмина служба доставки	Majo no Takkyuubin	Kiki's Delivery Service	Служба доставки Кики|Witch's Express Delivery|Ведьмина служба
513	Небесный замок Лапута	Tenkuu no Shiro Laputa	Castle in the Sky	Tenkuu no Shiro Rapyuta|Лапута
523	Мой сосед Тоторо	Tonari no Totoro	My Neighbor Totoro	My Neighbour Totoro|Тоторо
527	Покемон	Pokemon	Pokémon	Карманные монстры|Pocket Monsters|Indigo League|Adventures on the Orange Islands|The Johto Journeys|Johto League Champions|Master Quest
528	Покемон: Мьюту наносит ответный удар	Pokemon Movie 01: Mewtwo no Gyakushuu	Pokémon: The First Movie - Mewtwo Strikes Back	Gekijouban Pocket Monsters: Mewtwo Strikes Back|Pokémon Movie 1|Pokémon: The Origin of Mewtwo|Pokémon: The First Movie Kanzenban|Pokémon: The First Movie Complete Version
572	Навсикая из Долины ветров	Kaze no Tani no Nausicaa	Nausicaä of the Valley of the Wind	Наусика из Долины ветров|Nausicaa of the Valley of the Wind|Warriors of the Wind|Навсикая
578	Могила светлячков	Hotaru no Haka	Grave of the Fireflies	Tombstone for Fireflies
585	Шёпот сердца	Mimi wo Sumaseba	Whisper of the Heart	If You Listen Carefully
597	Возвращение кота	Neko no Ongaeshi	The Cat Returns	Кошачья благодарность|The Cat's Repayment
759	Однажды в Токио	Tokyo Godfathers	Tokyo Godfathers	Крёстные отцы Токио|Токийские крёстные отцы
777	Хеллсинг OVA	Hellsing Ultimate	Hellsing Ultimate	Хеллсинг Ultimate|Хеллсинг Ультимейт|Хеллсинг Ова
790	Эрго Прокси	Ergo Proxy	Ergo Proxy	
801	Призрак в доспехах: Синдром одиночки 2	Koukaku Kidoutai: Stand Alone Complex 2nd GIG	Ghost in the Shell: Stand Alone Complex 2nd GIG	Ghost In The Shell S.A.C. 2nd GIG|Призрак в доспехах: Синдром одиночки|Призрак в доспехах сериал
813	Драконий жемчуг Зет	Dragon Ball Z	Dragon Ball Z	DBZ|Dragonball Z|Драконий жемчуг Z|Драгон Болл Зет|Драгонболл Зет
820	Легенда о героях Галактики	Ginga Eiyuu Densetsu	Legend of the Galactic Heroes	LoGH|LotGH|Gin'eiden|GinEiDen|Heldensagen Vom Kosmosinsel|Легенда о галактических героях
849	Меланхолия Харухи Судзумии	Suzumiya Haruhi no Yuuutsu	The Melancholy of Haruhi Suzumiya	Харухи
853	Клуб свиданий старшей школы Оран	Ouran Koukou Host Club	Ouran High School Host Club	Гостевой клуб лицея Оран|Хост-клуб Оранской школы|Ohran Koko Host Club|Ouran Koukou Hosutobu|Ouran Koukou Host Bu|OHSHC|Хост клуб|Оран хост клуб
877	Нана	Nana	Nana	
889	Пираты «Чёрной лагуны»	Black Lagoon	Black Lagoon	Чёрная лагуна|Черная лагуна|Блэк Лагун
918	Гинтама	Gintama	Gintama	Gin Tama|Silver Soul|Yorinuki Gintama-san|Гинтама 1 сезон
934	Когда плачут цикады	Higurashi no Naku Koro ni	Higurashi: When They Cry	When the Cicadas Cry|The Moment the Cicadas Cry|Хигураси|Хигураши
1195	Подручный Луизы-Нулизы	Zero no Tsukaima	The Familiar of Zero	Подручный бездарной Луизы|Zero's Familiar|Нулизы
1210	Добро пожаловать в NHK	NHK ni Youkoso!	Welcome to the N.H.K.	Добро пожаловать в Эн.Эйч.Кэй.|Welcome to the NHK|Добро пожаловать в Эн-Эйч-Кей|Добро пожаловать в НХК
1482	Ди Грэй-мен	D.Gray-man	D.Gray-man	D. Gray-man|D. Grey-man|Ди Грей-мен|Ди Грэй мен|Д.Грэй-мен
1535	Тетрадь смерти	Death Note	Death Note	DN|Дэс ноут|Дес ноут|Блокнот смерти
1575	Код Гиас: Восставший Лелуш	Code Geass: Hangyaku no Lelouch	Code Geass: Lelouch of the Rebellion	Code Geass|Код Гиас|Код Гиасс|Код Гиасс: Восставший Лелуш|Код Гиас 1 сезон
1686	Блич: Воспоминания ни о ком	Bleach Movie 1: Memories of Nobody	Bleach the Movie: Memories of Nobody	Блич. Фильм 1|Блич: Чьи-то воспоминания|Gekijouban Bleach: Memories of Nobody
1689	Пять сантиметров в секунду	Byousoku 5 Centimeter	5 Centimeters per Second	Five Centimeters Per Second|Byousoku 5 Centimeter - a chain of short stories about their distance|5 Centimetres Per Second|5 cm per second|5 сантиметров в секунду
1735	Наруто: Ураганные хроники	Naruto: Shippuuden	Naruto Shippuden	Naruto Hurricane Chronicles|Наруто Ураганные хроники|Наруто Шиппуден|Наруто Шипуден|Наруто 2|Наруто 2 сезон
1818	Клеймор	Claymore	Claymore	Клэймор
1887	Счастливая звезда	Lucky☆Star	Lucky☆Star	Lucky Star
1943	Паприка	Paprika	Paprika	
2001	Гуррен-Лаганн, пронзающий небеса	Tengen Toppa Gurren Lagann	Gurren Lagann	Tengen Toppa Gurren-Lagann|Making Break-Through Gurren Lagann|Heavenly Breakthrough Gurren Lagann|TTGL|Gurren Laggan|Гуррен-Лаганн|Гуррен Лаганн|Гурен Лаган
2025	Темнее чёрного	Darker than Black: Kuro no Keiyakusha	Darker than Black	Темнее черного|Даркер зен Блэк
2034	Трогательный комплекс	Lovely★Complex	Lovely Complex	Love★Com|Love Com
2167	Кланнад	Clannad	Clannad	Кланнад 1 сезон
2236	Девочка, покорившая время	Toki wo Kakeru Shoujo	The Girl Who Leapt Through Time	Toki wo Kakeru Shojo|TokiKake|Toki o Kakeru Shojo|The Girl Who Cut Time|The Little Girl Who Conquered Time
2251	Шумиха!	Baccano!	Baccano!	Шумиха|Баккано|Бакано
2418	Меч чужака	Stranger: Mukou Hadan	Sword of the Stranger	
2472	Наруто: Ураганные хроники 1 — Адепты Тёмного царства	Naruto: Shippuuden Movie 1	Naruto Shippuden the Movie 1	Naruto Shippuden Movie|Naruto Movie 4|Gekijouban Naruto Shippuuden
2476	Школьные дни	School Days	School Days	Скул Дэйс
2593	Граница пустоты 1: Вид с высоты	Kara no Kyoukai Movie 1: Fukan Fuukei	The Garden of Sinners Chapter 1: Overlooking View	Граница пустоты: Сад грешников. Фильм|Kara no Kyoukai: The Garden of Sinners Movie 1|Borderline of Emptiness: Overlooking View|The Garden of Sinners: Thanatos
2759	Евангелион 1.11: Ты (не) один	Evangelion Movie 1: Jo	Evangelion: 1.0 You Are (Not) Alone	Евангелион: 1.0 Ты (не) один|Evangelion Shin Gekijouban: Jo|Rebuild of Evangelion: 1.0 You Are (Not) Alone|Evangelion: 1.01 You Are (Not) Alone|Evangelion: 1.11 You Are (Not) Alone|Евангелион 1.11|Евангелион 1.0|Евангелион: Ты не один
2890	Рыбка Поньо на утёсе	Gake no Ue no Ponyo	Ponyo	Ponyo on the Cliff by the Sea
2904	Код Гиас: Восставший Лелуш 2	Code Geass: Hangyaku no Lelouch R2	Code Geass: Lelouch of the Rebellion R2	Code Geass: Hangyaku no Lelouch 2nd Season|Code Geass: Hangyaku no Lelouch Second Season|Код Гиас R2|Код Гиасс R2|Код Гиас 2|Код Гиас 2 сезон|Код Гиас: Восставший Лелуш R2
2966	Волчица и пряности	Ookami to Koushinryou	Spice and Wolf	Волчица и пряности 1 сезон
2993	Розарио + Вампир	Rosario to Vampire	Rosario + Vampire	Rosario and Vampire
3002	Кайдзи	Gyakkyou Burai Kaiji: Ultimate Survivor	Kaiji: Ultimate Survivor	Кайдзи: Чудом выживший|Tobaku Mokushiroku Kaiji|The Suffering Pariah Kaiji|Кайдзи: Абсолютный выживший|Кайджи
3455	Любовные неприятности	To LOVE-Ru	To Love Ru	Toraburu|Love Trouble
3457	Рыцарь-вампир	Vampire Knight	Vampire Knight	Vampire Kishi|Vanpaia Naito|Рыцарь вампир
3588	Пожиратель душ	Soul Eater	Soul Eater	Соул Итер|Соул Итэр
3784	Евангелион 2.22: Ты (не) пройдёшь	Evangelion Movie 2: Ha	Evangelion: 2.0 You Can (Not) Advance	Евангелион: 2.0 Ты (не) пройдёшь|Evangelion Shin Gekijouban: Ha|Rebuild of Evangelion: 2.0 You Can (Not) Advance|Evangelion 2.22
3785	Евангелион 3.33: Ты (не) исправишь	Evangelion Movie 3: Q	Evangelion: 3.0 You Can (Not) Redo	Евангелион: 3.0 Ты (не) исправишь|Evangelion Shin Gekijouban: Kyuu|Rebuild of Evangelion: 3.0|Evangelion: 3.0 Q Quickening|Evangelion 3.33
3786	Евангелион 3.0+1.01: Как-то раз	Shin Evangelion Movie://	Evangelion: 3.0+1.0 Thrice Upon a Time	Евангелион: 3.0+1.01 — Как-то раз|Евангелион 4.44: Финал|Evangelion: 4.0|Rebuild of Evangelion|Shin Evangelion Gekijouban: //
4181	Кланнад: Продолжение истории	Clannad: After Story	Clannad: After Story	Кланнад 2|Кланнад афтер стори
4224	Торадора!	Toradora!	Toradora!	Тигр против дракона|Tiger X Dragon|Торадора|Тигр и дракон
4437	Наруто: Ураганные хроники 2 — Связи	Naruto: Shippuuden Movie 2 - Kizuna	Naruto Shippuden the Movie 2: Bonds	Наруто 5: Связи|Наруто 5: Узы|Naruto Movie 5|Naruto Shippuuden Movie 2|Naruto Shippuuden: Bonds
4654	Индекс волшебства	Toaru Majutsu no Index	A Certain Magical Index	Некий магический индекс|Toaru Majutsu no Kinsho Mokuroku|Некий магический Индекс|Индекс
4898	Тёмный дворецкий	Kuroshitsuji	Black Butler	Kuro Shitsuji|Kuroshitsuzi|Темный дворецкий|Чёрный дворецкий|Тёмный дворецкий 1 сезон
5081	Истории монстров	Bakemonogatari	Bakemonogatari	Ghostory|Monstory|Бакемоногатари|Моногатари
5114	Стальной алхимик: Братство	Fullmetal Alchemist: Brotherhood	Fullmetal Alchemist: Brotherhood	Цельнометаллический алхимик: Братство|Hagane no Renkinjutsushi: Fullmetal Alchemist|Fullmetal Alchemist (2009)|FMA|FMAB|Стальной алхимик Братство|Цельнометаллический алхимик|Фулметал алхимик|ФМА|Стальной алхимик 2
5680	Кэйон!	K-On!	K-ON!	Клуб лёгкой музыки|Keion|K-ON! Season 1|Кэйон|Лёгкая музыка|Легкая музыка|К-Он
5681	Летние войны	Summer Wars	Summer Wars	
6045	Достучаться до тебя	Kimi ni Todoke	Kimi ni Todoke: From Me to You	Дотянуться до тебя|Reaching You|Кими ни Тодоке
6213	Некий научный Рейлган	Toaru Kagaku no Railgun	A Certain Scientific Railgun	Простой научный рейлган|Toaru Kagaku no Choudenjihou|Некий научный Рейлган 1 сезон|Рейлган
6347	Дурни, тесты, аватары	Baka to Test to Shoukanjuu	Baka & Test: Summon the Beasts	Дурак, тест и призванные существа|Балбес, тесты и призванные существа|The Idiot, the Tests and the Summoned Creatures|Baka to Test to Shokanju|BakaTest
6547	Ангельские ритмы!	Angel Beats!	Angel Beats!	Ангельские ритмы|Энджел Битс
6675	Красная черта	Redline	Redline	Red line
6702	Хвост Феи	Fairy Tail	Fairy Tail	Сказка о Хвосте феи|Фейри Тейл|Хвост феи|Сказка о хвосте феи|Хвост феи 1 сезон
6746	Дюрарара!!	Durarara!!	Durarara!!	Всадник без головы|Dhurarara!!|Dyurarara!!|Dulalala!!|Dullalala!!|DRRR!!|Дюрарара
6880	Страна чудес смертников	Deadman Wonderland	Deadman Wonderland	Deddoman Wandarando|Дэдмен Вандерленд
7054	Президент студсовета — горничная!	Kaichou wa Maid-sama!	Maid Sama!	Староста-горничная|Президент студенческого совета — горничная!|Президент — горничная!|Class President is a Maid!|Староста горничная|Президент студсовета — горничная
7311	Исчезновение Харухи Судзумии	Suzumiya Haruhi no Shoushitsu	The Disappearance of Haruhi Suzumiya	The Vanishment of Haruhi Suzumiya|Suzumiya Haruhi no Syoshitsu|Haruhi Movie|Исчезновение Харухи
7674	Бакуман	Bakuman.	Bakuman.	Bakuman Season 1|Бакуман 1 сезон
7711	Ариэтти из страны лилипутов	Karigurashi no Arrietty	The Secret World of Arrietty	Добывайка Ариэтти|Karigurashi no Arrietti|The Borrower Arrietty
7724	Усопшие	Shiki	Shiki	Corpse Demon|Сики|Шики
7791	Кэйон!!	K-On!!	K-ON! Season 2	Клуб лёгкой музыки 2|Кэйон!! 2|Keion 2|K-On!! 2nd Season
8074	Школа мертвецов	Highschool of the Dead	High School of the Dead	Школа мертвяков|Школа мёртвых|Gakuen Mokushiroku: Highschool of the Dead|HOTD|HSOTD|Старшая школа мертвецов|Хай скул оф зе дэд
8525	Одному лишь Богу ведомый мир	Kami nomi zo Shiru Sekai	The World God Only Knows	Kaminomi
8769	Ну не может моя сестрёнка быть такой милой	Ore no Imouto ga Konnani Kawaii Wake ga Nai	OreImo	Ну не может моя сестрёнка быть такой милой, и всё тут!|Моя сестрёнка не может быть такой милашкой|My Little Sister Can't Be This Cute|Моя младшая сестра не может быть такой милой|Орэимо|Ореимо
8841	Уж не зомби ли это?	Kore wa Zombie desu ka?	Is This a Zombie?	Koreha Zombie Desuka?|Kore ha Zombie Desu ka?|Kore wa Zombie Desuka?
9041	Бесконечные небеса	IS: Infinite Stratos	Infinite Stratos	Необъятные небеса|IS
9253	Врата Штейна	Steins;Gate	Steins;Gate	Штейнс Гейт|Врата Штайна|Врата Штейна;
9260	Истории ран. Часть 1: Железная кровь	Kizumonogatari I: Tekketsu-hen	Kizumonogatari Part 1: Iron-Blooded	Koyomi Vamp
9513	Вельзепуз	Beelzebub	Beelzebub	Вельзевул|Бельзевул
9617	Кэйон в кино!	K-On! Movie	K-ON! The Movie	Клуб лёгкой музыки в кино!|K-On! Фильм|Eiga K-On!|Keion Movie
9756	Девочка-волшебница Мадока★Волшебство	Mahou Shoujo Madoka★Magica	Puella Magi Madoka Magica	Mahou Shoujo Madoka Magika|Magical Girl Madoka Magica|Девочка-волшебница Мадока Магика|Мадока Магика|Мадока|Волшебница Мадока
9919	Синий экзорцист	Ao no Exorcist	Blue Exorcist	Ao no Futsumashi|Голубой экзорцист
9989	Невиданный цветок	Ano Hi Mita Hana no Namae wo Bokutachi wa Mada Shiranai.	Anohana: The Flower We Saw That Day	А нам всё невдомёк, как же звался тот цветок|AnoHana|We Still Don't Know the Name of the Flower We Saw That Day.|Ано Хана|Анохана|Мы всё ещё не знаем названия цветка
10087	Судьба/Начало	Fate/Zero	Fate/Zero	Судьба: Начало|Фейт Зеро|Фейт/Зеро
10165	Мелочи жизни	Nichijou	Nichijou - My Ordinary Life	Everyday|Повседневность|Нитидзё
10408	В лес, где мерцают светлячки	Hotarubi no Mori e	Into the Forest of Fireflies' Light	В лесу мерцания светлячков|The Light of a Firefly Forest|В лес где мерцают светлячки|Лес светлячков
10620	Дневник будущего	Mirai Nikki (TV)	The Future Diary	Mirai Nikki|Mirai Nikki (2011)|Future Diary|Мирай Никки
10719	У меня мало друзей	Boku wa Tomodachi ga Sukunai	Haganai: I don't have many friends	I Don't Have Many Friends
10721	Пингвиний барабан	Mawaru Penguindrum	Penguindrum	Вращающийся пингвинячий барабан|Пингвиндрам
10793	Корона грешника	Guilty Crown	Guilty Crown	Корона вины|Корона греха|Гилти Краун
10800	Яркая Тихая	Chihayafuru	Chihayafuru	Игра Тихайи|Chihayafull|Тихаяфуру|Чихаяфуру
11061	Охотник х Охотник (2011)	Hunter x Hunter (2011)	Hunter x Hunter	HxH (2011)|Хантер х Хантер|Охотник х Охотник|Охотник на охотников|Хантер Хантер|ХхХ|Хантер х Хантер 2011
11111	Иная	Another	Another	Другая|Анозер
11499	Санка Рэа	Sankarea	Sankarea: Undying Love	
11577	Врата Штейна: Зона загрузки дежавю	Steins;Gate Movie: Fuka Ryouiki no Dejà vu	Steins;Gate: The Movie - Load Region of Déjà Vu	Врата Штейна: Область загрузки дежавю|Steins Gate Movie
11597	Истории подделок	Nisemonogatari	Nisemonogatari	Impostory
11617	Старшая школа DxD	High School DxD	High School DxD	Демоны старшей школы|Старшая школа: Демоны против падших|Highschool DxD|ДхД|Хай скул ДхД
11633	Кровавый парень	Blood Lad	Blood Lad	
11737	Синий экзорцист. Фильм	Ao no Exorcist Movie	Blue Exorcist: The Movie	Ao no Exorcist Gekijouban|Ao no Futsumashi Movie|Blue Exorcist Movie
11741	Судьба/Начало 2	Fate/Zero 2nd Season	Fate/Zero Season 2	Fate/Zero Second Season|Фейт Зеро 2
11757	Мастера Меча Онлайн	Sword Art Online	Sword Art Online	Искусство Меча Онлайн|S.A.O|SAO|Мастера меча онлайн|САО|Сао|Искусство меча онлайн|Мастера меча онлайн 1 сезон
11759	Ускоренный мир	Accel World	Accel World	Accelerated World
11771	Баскетбол Куроко	Kuroko no Basket	Kuroko's Basketball	Баскетбол, в который играет Куроко|Kuroko no Basuke|KuroBas|Куроко|Баскетбол Куроко 1 сезон
11843	Повседневная жизнь старшеклассников	Danshi Koukousei no Nichijou	Daily Lives of High School Boys	Будни старшеклассников
11887	Связь сердец	Kokoro Connect	Kokoro Connect	Kokoroco
11981	Девочка-волшебница Мадока★Волшебный фильм 3: История восстания	Mahou Shoujo Madoka★Magica Movie 3: Hangyaku no Monogatari	Puella Magi Madoka Magica the Movie: Rebellion	Mahou Shoujo Madoka Magika Movie 3|Magical Girl Madoka Magica Movie 3
12189	Хёка	Hyouka	Hyouka	Хёка: Тебе не сбежать|Хёка: Тебе не уйти|Hyou-ka|Hyouka: You can't escape|Hyou-ka: You can't escape|Hyoka|Хьёка|Хиока
12355	Волчьи дети Амэ и Юки	Ookami Kodomo no Ame to Yuki	Wolf Children	The Wolf Children Ame and Yuki|Волчьи дети
12477	Патэма наоборот	Sakasama no Patema	Patema Inverted	Перевёрнутая Патэма
12859	Ван-Пис: Z	One Piece Film: Z	One Piece Film: Z	One Piece Movie 12
13125	Из нового света	Shinsekai yori	From the New World	Из нового мира|Shin Sekai yori|Новый мир
13601	Психопаспорт	Psycho-Pass	Psycho-Pass	Psychopath|Saiko Pasu|Психо-пасс|Психопасс|Психо пасс
13667	Наруто: Ураганные хроники 6 — Путь ниндзя	Naruto: Shippuuden Movie 6 - Road to Ninja	Naruto Shippuden the Movie 6: Road to Ninja	Naruto Movie 9
13759	Кошечка из Сакурасо	Sakura-sou no Pet na Kanojo	The Pet Girl of Sakurasou	Sakurasou no Pet na Kanojo
14075	Буря потерь	Zetsuen no Tempest	Blast of Tempest	Буря потерь: Гибель человечества|Буря потерь: Истребление цивилизации|Zetsuen no Tempest: The Civilization Blaster
14227	Чудовище за соседней партой	Tonari no Kaibutsu-kun	My Little Monster	Монстр за соседней партой|Tonari no Kaibutsukun|The Monster Next Door|My Neighbor Monster-kun|Мой маленький монстр|Монстр по соседству
14289	Скажи: «Я люблю тебя»	Suki tte Ii na yo.	Say "I Love You."	Suki-tte Ii na yo.|Sukinayo
14345	Бтууум!	Btooom!	BTOOOM!	Взрыв!|Бабах!
14349	Академия ведьмочек. Фильм	Little Witch Academia		Wakate Animator Ikusei Project|2012 Young Animator Training Project|Anime Mirai 2012|LWA
14467	Проект Кей	K	K	K-Project|K -eine weitere Geschichte-
14513	Маги: Лабиринт магии	Magi: The Labyrinth of Magic	Magi: The Labyrinth of Magic	Magi Season 1|Маги: Лабиринт волшебства|Маги|Лабиринт магии
14713	Очень приятно, Бог	Kamisama Hajimemashita	Kamisama Kiss	Приятно познакомиться, Бог
14719	Невероятное приключение ДжоДжо	JoJo no Kimyou na Bouken (TV)	JoJo's Bizarre Adventure (2012)	JoJo no Kimyou na Bouken (2012)|JoJo's Bizarre Adventure: The Animation|JoJo|Невероятные приключения ДжоДжо|Приключения ДжоДжо|ДжоДжо|Джоджо|Невероятные приключения ДжоДжо 1 сезон
14741	Чудачества любви не помеха!	Chuunibyou demo Koi ga Shitai!	Love, Chunibyo & Other Delusions!	Я не от мира сего, но тоже хочу любить|Она подросток, но я люблю её!|Chu-2 Byo demo Koi ga Shitai!|Regardless of My Adolescent Delusions of Grandeur, I Want a Date!|Чудачество любви не помеха|Чуни|Чунибьё|Чунибё
14813	Как и ожидалось, моя школьная романтическая жизнь не удалась	Yahari Ore no Seishun Love Comedy wa Machigatteiru.	My Teen Romantic Comedy SNAFU	Розовая пора моей школьной жизни — сплошной обман|Жизнь — любовное кино, но какое-то не то...|Как я и ожидал, моя школьная жизнь не задалась|Как и ожидалось, моя подростковая романтическая комедия не складывается|Как я и думал, с романтической комедией моей юности что-то не так|Oregairu|My youth romantic comedy is wrong as I expected.|Орегайру|Моя школьная романтическая жизнь не удалась
15039	Невиданный цветок. Фильм	Ano Hi Mita Hana no Namae wo Bokutachi wa Mada Shiranai. Movie	Anohana: The Flower We Saw That Day The Movie	AnoHana Movie|We Still Don't Know the Name of the Flower We Saw That Day. Movie
15451	Старшая школа DxD New	High School DxD New	High School DxD New	High School DxD Dai 2-ki|High School DxD 2nd Season|High School DxD Second Season|Highschool DxD 2
15583	Рандеву с жизнью	Date A Live	Date A Live	Свидание с духом|Дэйт э Лайв
15809	Повелитель тьмы на подработке!	Hataraku Maou-sama!	The Devil is a Part-Timer!	Сатана на подработке!|Сатана на полставки!|Князь тьмы меняет профессию!|Работящий Лорд-Демон!|Сатана на подработке|Повелитель тьмы на подработке
16067	Безоблачное завтра	Nagi no Asu kara	A Lull in the Sea	Когда успокоится море|Из штиля завтрашнего дня|From The Calm Tomorrow|Nagi-Asu: A Lull in the Sea|Nagi no Asukara|Nagiasu|Наги но Асукара
16498	Атака титанов	Shingeki no Kyojin	Attack on Titan	Вторжение гигантов|Атакующий титан|Вторжение титанов|AoT|Атака на титанов|АоТ|СнК|Сингеки но Кёдзин|Сингеки но Кьёджин|Атака титанов 1 сезон
16592	Данганронпа: Школа надежды и безнадёжные школьники	Danganronpa: Kibou no Gakuen to Zetsubou no Koukousei The Animation	Danganronpa: The Animation	Данганронпа|Школа отчаяния|Пуля-доказательство: Академия надежды и отчаявшиеся старшеклассники|Опровергающая пуля: Академия надежды и отчаявшиеся старшеклассники|Dangan Ronpa: The Animation|Данганронпа: Академия
16662	Ветер крепчает	Kaze Tachinu	The Wind Rises	
16742	Не моя вина, что я не популярна!	Watashi ga Motenai no wa Dou Kangaetemo Omaera ga Warui!	WataMote: No Matter How I Look At It, It's You Guys' Fault I'm Not Popular!	Как ни смотри, это всё вы виноваты, что я не популярна!|Watashi ga Motenai no wa Dou Kangaete mo Omaera ga Warui!|It's Not My Fault That I'm Not Popular!|WataMote
16782	Сад изящных слов	Kotonoha no Niwa	The Garden of Words	Koto no Ha no Niwa|The Garden of Kotonoha|Сад слов
16870	Наруто: Последний фильм	The Last: Naruto the Movie	Naruto Shippuden the Movie 7: The Last	Naruto Movie 10: Naruto the Movie: The Last,Naruto: Shippuuden Movie 7 - The Last
16894	Баскетбол Куроко 2	Kuroko no Basket 2nd Season	Kuroko's Basketball 2	Баскетбол, в который играет Куроко 2|Kuroko no Basuke 2nd Season
17074	Цикл историй: Второй сезон	Monogatari Series: Second Season	Monogatari Series: Second Season	Истории монстров 2|Nekomonogatari: Shiro|Kabukimonogatari|Otorimonogatari|Onimonogatari|Koimonogatari
17265	Покорение горизонта	Log Horizon	Log Horizon	Хроники Горизонта|Лог Горизонта|Логин Горизонт|За горизонтом|Лог Горизонт
17729	Плод Грисайи	Grisaia no Kajitsu	The Fruit of Grisaia	Натюрморт в серых тонах|Le Fruit de la Grisaia
17895	Золотая пора	Golden Time	Golden Time	Золотое время|Голден Тайм
18115	Маги: Королевство магии	Magi: The Kingdom of Magic	Magi: The Kingdom of Magic	Маги: Царство магии|Magi: The Labyrinth of Magic 2|Magi Season 2
18153	По ту сторону границы	Kyoukai no Kanata	Beyond the Boundary	За гранью|Beyond the Horizon|Кёкай но Каната
18277	Удар крови	Strike the Blood	Strike the Blood	SutoBura
18507	Вольный стиль!	Free!	Free! - Iwatobi Swim Club	Свободный стиль!|Всплеск!|Плавательный клуб старшей школы Иватоби
18671	Чудачества любви не помеха! 2	Chuunibyou demo Koi ga Shitai! Ren	Love, Chunibyo & Other Delusions!: Heart Throb	Chuunibyou demo Koi ga Shitai! 2|Chu-2 Byo demo Koi ga Shitai! Ren
18679	Убей или умри	Kill la Kill	Kill la Kill	Круши, кромсай|Убить или быть убитым|Dressed to Kill|KLK|Килл ла Килл|Кил ла Кил
18897	Притворная любовь	Nisekoi	Nisekoi: False Love	Любовь понарошку|Нисекой|Фальшивая любовь
19163	Рандеву с жизнью 2	Date A Live II	Date A Live II	Date A Live 2
19775	Рыцари Сидонии	Sidonia no Kishi	Knights of Sidonia	Сидония
19815	Нет игры — нет жизни	No Game No Life	No Game, No Life	Без игры жизни нет|Без игры — нет жизни|Игра на выживание|NGNL|Nogenora|Нет игры нет жизни|Ноу гейм ноу лайф
20507	Бездомный бог	Noragami	Noragami	Норагами|Бездомный бог 1 сезон
20583	Волейбол!!	Haikyuu!!	Haikyu!!	High Kyuu!!|HQ!!|Волейбол|Хайкю|Хайкью|Волейбол 1 сезон
20785	Непутёвый ученик в школе магии	Mahouka Koukou no Rettousei	The Irregular at Magic High School	Посредственность из школы магов|Бездарный ученик старшей школы магии|Бездарь в старшей школе магии|Непутевый ученик в школе магии|Непутёвый ученик|Махока
20787	Чёрная пуля	Black Bullet	Black Bullet	
20899	Невероятное приключение ДжоДжо: Рыцари звёздной пыли	JoJo no Kimyou na Bouken Part 3: Stardust Crusaders	JoJo's Bizarre Adventure: Stardust Crusaders	JoJo's Bizarre Adventure Part 3
21339	Психопаспорт. Фильм	Psycho-Pass Movie 1	Psycho-Pass: The Movie	Psychopath Movie
21557	Воспоминания о Марни	Omoide no Marnie	When Marnie Was There	
21647	История любви Тамако	Tamako Love Story		Тамако: История любви|Tamako Market Movie
21881	Мастера Меча Онлайн II	Sword Art Online II	Sword Art Online II	Искусство Меча Онлайн 2|Мастера Меча Онлайн 2|SAO 2|Phantom Bullet|SAO II|Sword Art Online 2|Мастера меча онлайн 2|Мастера меча онлайн 2 сезон|САО 2
21995	Неудержимая юность	Ao Haru Ride	Blue Spring Ride	Дорога юности|Aoharaido|Ао Хару Райд
22043	Хвост Феи (2014)	Fairy Tail (2014)	Fairy Tail Series 2	Сказка о Хвосте феи (2014)|Хвост Феи 2|Фейри Тейл 2|Fairy Tail Season 2
22147	Великолепный парк Амаги	Amagi Brilliant Park	Amagi Brilliant Park	Amaburi
22199	Убийца Акамэ!	Akame ga Kill!	Akame ga Kill!	Akame ga Kiru!|Убийца Акаме|Убийца Акаме!|Акаме га Кил|Акамэ га Киру
22297	Судьба/Ночь схватки: Бесконечный мир клинков	Fate/stay night: Unlimited Blade Works	Fate/stay night [Unlimited Blade Works]	Судьба/Ночь схватки: Клинков бесконечный край|Fate/stay night (2014)|Fate - Stay Night|Фейт Стей Найт UBW|Бесконечный мир клинков
22319	Токийский гуль	Tokyo Ghoul	Tokyo Ghoul	Токийский монстр|Tokyo Kushu|Toukyou Kushu|Toukyou Ghoul|Токио гуль|Токийский гуль 1 сезон
22535	Паразит: Учение о жизни	Kiseijuu: Sei no Kakuritsu	Parasyte: The Maxim	Parasite|Parasitic Beasts|Parasyte|Паразит|Паразиты
22729	Альдноа.Зеро	Aldnoah.Zero	Aldnoah.Zero	AZ|Альдноа Зеро|Алдноа
22789	Баракамон	Barakamon	Barakamon	
23233	По велению адской сестры	Shinmai Maou no Testament	The Testament of Sister New Devil	Новый завет владыки тьмы, моей сестры|Моей сестрёнкой стала Повелительница демонов|Shinmai Maou no Keiyakusha
23273	Твоя апрельская ложь	Shigatsu wa Kimi no Uso	Your Lie in April	Твои апрельские грёзы|Апрель — это твоя ложь|Kimiuso|Апрельская ложь
23277	Как воспитать героиню из обычной девушки	Saenai Heroine no Sodatekata	Saekano: How to Raise a Boring Girlfriend	Как создать скучную героиню|Saenai Kanojo no Sodate-kata
23281	Психопаспорт 2	Psycho-Pass 2	Psycho-Pass 2	Psycho-Pass Second Season|Psychopath 2nd Season
23283	Эхо террора	Zankyou no Terror	Terror in Resonance	Токийский террор|Резонанс ужаса|Террор в Токио|Terror in Tokyo|Terror of Resonance
23289	Ежемесячное сёдзё Нодзаки	Gekkan Shoujo Nozaki-kun	Monthly Girls' Nozaki-kun	Нодзаки — автор сёдзё-манги|Нодзаки и его сёдзё-манга|Ежемесячное сёдзё Нодзаки-куна|Нодзаки кун|Нозаки кун
23321	Покорение горизонта 2	Log Horizon 2nd Season	Log Horizon 2	Log Horizon Second Season|Log Horizon Dai 2 Series
23755	Семь смертных грехов	Nanatsu no Taizai	The Seven Deadly Sins	Нанацу но Тайдзай|Семь смертных грехов 1 сезон
23847	Как и ожидалось, моя школьная романтическая жизнь не удалась 2	Yahari Ore no Seishun Love Comedy wa Machigatteiru. Zoku	My Teen Romantic Comedy SNAFU TOO!	Розовая пора моей школьной жизни — сплошной обман 2|Жизнь — любовное кино, но какое-то не то... 2|Как я и ожидал, моя школьная жизнь не задалась 2|Oregairu 2|My Teen Romantic Comedy SNAFU 2|Yahari Ore no Seishun Love Comedy wa Machigatteiru. Second Season|Yahari Ore no Seishun Love Comedy wa Machigatteiru. 2nd Season
24277	Трусливый велосипедист: Большая дорога	Yowamushi Pedal: Grande Road		Трусливый велосипедист 2|Yowamushi Pedal 2nd Season|Yowapeda 2nd Season|Трусливый велосипедист|Ёвамуси Педал
24415	Баскетбол Куроко 3	Kuroko no Basket 3rd Season	Kuroko's Basketball 3	Баскетбол, в который играет Куроко 3|Kuroko no Basuke 3rd Season
24439	Фронт кровавой блокады	Kekkai Sensen	Blood Blockade Battlefront	Стражи барьера|Bloodline Battlefront|Кеккай Сенсен
24703	Старшая школа DxD: Рождение	High School DxD BorN	High School DxD BorN	High School DxD Third Season|High School DxD 3rd Season|Highschool DxD BorN
24833	Класс убийц	Ansatsu Kyoushitsu	Assassination Classroom	Убийство в классной комнате|Убийственный класс|Класс убийц 1 сезон
25013	Йона на заре	Akatsuki no Yona	Yona of the Dawn	Рассвет Йоны|Yona: The girl standing in the blush of dawn
25157	Тринити: Семеро магов	Trinity Seven	Trinity Seven	Единство семи магов|Святая семёрка
25183	Гангста	Gangsta.	Gangsta.	Бандиты|Бандитос|Бандидос|Gyangusuta
25537	Судьба/Ночь схватки: Прикосновение небес	Fate/stay night Movie: Heaven's Feel - I. Presage Flower	Fate/stay night: Heaven's Feel - I. Presage Flower	
25777	Атака титанов 2	Shingeki no Kyojin Season 2	Attack on Titan Season 2	Вторжение гигантов 2|Атакующий титан 2|Вторжение титанов 2|AoT 2|Атака титанов 2 сезон
26055	Невероятное приключение ДжоДжо: Рыцари звёздной пыли 2	JoJo no Kimyou na Bouken Part 3: Stardust Crusaders - Egypt-hen	JoJo's Bizarre Adventure: Stardust Crusaders - Battle in Egypt	JoJo's Bizarre Adventure Part 3|JoJo's Bizarre Adventure: Stardust Crusaders - Egypt Arc
26243	Последний Серафим	Owari no Seraph	Seraph of the End: Vampire Reign	Серафим конца времён|Серафим конца|Seraph of the End
27775	Пластиковые воспоминания	Plastic Memories	Plastic Memories	Синтетические воспоминания|Plamemo|Пластик Меморис
27787	Притворная любовь 2	Nisekoi:	Nisekoi: False Love Season 2	Любовь понарошку 2|Nisekoi 2nd Season|Nisekoi Second Season
27899	Токийский гуль √A	Tokyo Ghoul √A	Tokyo Ghoul √A	Токийский монстр √A|Токийский гуль 2|Tokyo Ghoul Root A|Tokyo Ghoul 2nd Season|Tokyo Ghoul Second Season|Токийский гуль 2 сезон|Токийский гуль А
27989	Звучи, эуфониум!	Hibike! Euphonium	Sound! Euphonium	Играй, эуфониум!|Звучи эуфониум|Хибике Юфониум
28121	Может, я встречу тебя в подземелье?	Dungeon ni Deai wo Motomeru no wa Machigatteiru Darou ka	Is It Wrong to Try to Pick Up Girls in a Dungeon?	Разве плохо искать себе пару в подземелье?|В подземелье я пойду, там красавицу найду|Неужели искать встречи в подземелье — неправильно?|DanMachi|Is It Wrong That I Want to Meet You in a Dungeon|В подземелье я пойду там красавицу найду|Данмати|ДанМати|Подземелье
28171	Повар-боец Сома	Shokugeki no Souma	Food Wars! Shokugeki no Soma	В поисках божественного рецепта|Кулинарные поединки Сомы|Кухня Сомы|Shokugeki no Soma|Food Wars: Shokugeki no Soma|Сёкугэки но Сома
28223	Смертельный парад	Death Parade	Death Parade	Шествие смерти|Desu Parеdo|Парад смерти|Дэс Парад
28297	Моя история!	Ore Monogatari!!	My Love Story!!	My Story!!
28497	Герои шести лепестков	Rokka no Yuusha	Rokka: Braves of the Six Flowers	Герои шестицветия|Rokka no Yusha
28623	Кабанэри железной крепости	Koutetsujou no Kabaneri	Kabaneri of the Iron Fortress	Кабанери железной крепости|Кабанэри из стальной крепости
28675	По ту сторону границы: Я буду рядом — Будущее	Kyoukai no Kanata Movie 2: I'll Be Here - Mirai-hen	Beyond the Boundary: I'll Be Here - Future	За гранью: Я буду здесь — Будущее|За гранью: Я буду рядом — Будущее|За пределом: Будущее|Beyond the Boundary Movie|Kyokai no Kanata Movie
28677	Ямада-кун и семь ведьм	Yamada-kun to 7-nin no Majo	Yamada-kun and the Seven Witches	Yamada-kun to Nananin no Majo|Yamada-kun and the 7 Witches|Yamajo
28701	Судьба/Ночь схватки: Бесконечный мир клинков 2	Fate/stay night: Unlimited Blade Works 2nd Season	Fate/stay night [Unlimited Blade Works] Season 2	Судьба/Ночь схватки: Клинков бесконечный край 2|Fate/stay night (2015)|Fate - Stay Night
28725	Сердцу хочется кричать	Kokoro ga Sakebitagatterunda.	The Anthem of the Heart	Сердце хочет кричать|Сердцу хочется петь|Kokosake
28755	Боруто	Boruto: Naruto the Movie	Boruto: Naruto the Movie	Боруто: Наруто. Фильм|Gekijouban Naruto (2015)
28805	Ученик чудовища	Bakemono no Ko	The Boy and the Beast	Дитя чудовища|Child of a Beast|Бакэмоно но Ко
28825	Двуличная сестрёнка Умару!	Himouto! Umaru-chan	Himouto! Umaru-chan	My Two-Faced Little Sister|Двуличная сестрёнка Умару-чан|Двуличная сестренка Умару|Умару
28851	Форма голоса	Koe no Katachi	A Silent Voice	The Shape of Voice|Голос тишины
28891	Волейбол!! 2	Haikyuu!! Second Season	Haikyu!! 2nd Season	Волейбол 2|Волейбол 2 сезон|Хайкю 2
28907	Врата: Там бьются наши воины	Gate: Jieitai Kanochi nite, Kaku Tatakaeri	GATE	Gate: Thus the JSDF Fought There!
28927	Последний Серафим: Битва в Нагое	Owari no Seraph: Nagoya Kessen-hen	Seraph of the End: Battle in Nagoya	Seraph of the End: War in Nagoya|Owari no Seraph 2nd Season|Seraph of the End 2nd Season
28977	Гинтама 4	Gintama°	Gintama Season 4	Gintama' (2015)
28999	Шарлотта	Charlotte	Charlotte	
29786	Скучный мир, где не существует самой идеи похабных шуток	Shimoneta to Iu Gainen ga Sonzai Shinai Taikutsu na Sekai	SHIMONETA: A Boring World Where the Concept of Dirty Jokes Doesn't Exist	Скучный мир, в котором не существует самой концепции похабных шуток|Shimoseka
29803	Повелитель	Overlord	Overlord	Владыка|Over Lord|Оверлорд|Повелитель 1 сезон
30015	Повторная жизнь	ReLIFE	ReLIFE	Re LIFE|Реальная жизнь|Релайф|РеЛайф
30123	Красноволосая принцесса Белоснежка	Akagami no Shirayuki-hime	Snow White with the Red Hair	Akagami no Shirayukihime
30240	Школа-тюрьма	Prison School	Prison School	Школа строгого режима|Purizun Sukuru|Kangoku Gakuen
30276	Ванпанчмен	One Punch Man	One-Punch Man	One Punch-Man|OPM|Ван панч мен|Ван-Панч-Мен|Человек одного удара|Ванпанч|Ванпанчмен 1 сезон
30296	Доблесть рыцаря-неудачника	Rakudai Kishi no Cavalry	Chivalry of a Failed Knight	A Chivalry of the Failed Knight|Rakudai Kishi no Eiyuutan|A Tale of Worst One
30307	Повседневная жизнь с девушкой-монстром	Monster Musume no Iru Nichijou	Monster Musume: Everyday Life with Monster Girls	MonMusu
30484	Врата Штейна 0	Steins;Gate 0	Steins;Gate 0	Steins;Gate Zero|Врата Штейна ноль
30503	Бездомный бог: Арагото	Noragami Aragoto	Noragami Aragoto	Бездомный бог: Неистовство|Бездомный бог 2|Бездомный бог 2 сезон|Норагами 2
30544	Боевая академия города Астериск	Gakusen Toshi Asterisk	The Asterisk War	Война в Астериске|Academy Battle City Asterisk
30654	Класс убийц 2	Ansatsu Kyoushitsu 2nd Season	Assassination Classroom Second Season	Убийство в классной комнате 2|Ansatsu Kyoushitsu Season 2|Ansatsu Kyoushitsu Final Season|Класс убийц 2 сезон
30694	Драконий жемчуг: Супер	Dragon Ball Super	Dragon Ball Super	Dragon Ball Chou|DB Super|DBS|Драконий жемчуг Супер|Драгон Болл Супер
30831	Этот замечательный мир!	Kono Subarashii Sekai ni Shukufuku wo!	KonoSuba: God's Blessing on This Wonderful World!	Богиня благословляет этот прекрасный мир|Этот прекрасный мир|Give Blessings to This Wonderful World!|Коносуба|Этот замечательный мир|Благословение этому прекрасному миру|Коносуба 1 сезон
31043	Город, в котором меня нет	Boku dake ga Inai Machi	Erased	Город, в котором пропал лишь я|The Town Where Only I am Missing|BokuMachi|Город в котором меня нет|Стёртый
31240	Re:Zero. Жизнь с нуля в альтернативном мире	Re:Zero kara Hajimeru Isekai Seikatsu	Re:ZERO -Starting Life in Another World-	С нуля: Пособие по выживанию в альтернативном мире|Re: Жизнь в альтернативном мире с нуля|Re: Life in a different world from zero|ReZero|Ре Зеро|Ре:Зеро|Жизнь с нуля в другом мире|Жизнь в альтернативном мире с нуля|Ре зеро 1 сезон|Рэ Зэро
31478	Великий из бродячих псов	Bungou Stray Dogs	Bungo Stray Dogs	Бродячие псы: Литературные гении|Бродячие псы литературы|Literary Stray Dogs|Бродячие псы|Проза бродячих псов|Бунго Стрей Догс
31580	Нелюдь	Ajin	Ajin: Demi-Human	Полулюди|Получеловек
31646	Мартовский лев	3-gatsu no Lion	March Comes In Like a Lion	Март приходит подобно льву|Sangatsu no Lion|Март приходит, как лев|Сангацу но Лайон
31658	Баскетбол Куроко: Последняя игра	Kuroko no Basket Movie 4: Last Game	Kuroko's Basketball the Movie: Last Game	Gekijouban Kuroko no Basuke: Last Game|The Basketball Which Kuroko Plays
31722	Семь смертных грехов: Знамение священной войны	Nanatsu no Taizai: Seisen no Shirushi	The Seven Deadly Sins: Signs of Holy War	
31757	Истории ран. Часть 2: Горячая кровь	Kizumonogatari II: Nekketsu-hen	Kizumonogatari Part 2: Hot-Blooded	Koyomi Vamp|Kizumonogatari Part 2
31758	Истории ран. Часть 3: Холодная кровь	Kizumonogatari III: Reiketsu-hen	Kizumonogatari Part 3: Cold-Blooded	Koyomi Vamp
31765	Мастера Меча Онлайн: Порядковый ранг	Sword Art Online Movie: Ordinal Scale	Sword Art Online the Movie: Ordinal Scale	Искусство Меча Онлайн: Порядковый ранг|Gekijouban Sword Art Online
31798	Кизнайвер	Kiznaiver	Kiznaiver	Связанные
31859	Гримгал пепла и иллюзий	Hai to Gensou no Grimgar	Grimgar: Ashes and Illusions	Гримгар из пепла и иллюзий|Grimgal of Ashes and Fantasies
31933	Невероятное приключение ДжоДжо: Несокрушимый алмаз	JoJo no Kimyou na Bouken Part 4: Diamond wa Kudakenai	JoJo's Bizarre Adventure: Diamond Is Unbreakable	Diamond is not Crash|ДжоДжо: Несокрушимый алмаз|Джоджо 4|Несокрушимый алмаз
31964	Моя геройская академия	Boku no Hero Academia	My Hero Academia	Геройская академия|МГА|Боку но Хиро Академия|Моя геройская академия 1 сезон
32182	Моб Психо 100	Mob Psycho 100	Mob Psycho 100	Mob Psycho Hyaku|Mob Psycho One Hundred|Моб Психо|Моб Сайко 100|Моб Психо 100 1 сезон
32281	Твоё имя	Kimi no Na wa.	Your Name.	Твое имя|Кими но На ва
32282	Повар-боец Сома: Второе блюдо	Shokugeki no Souma: Ni no Sara	Food Wars! The Second Plate	В поисках божественного рецепта 2|Кулинарные поединки Сомы 2|Кухня Сомы 2|Shokugeki no Souma 2nd Season|Shokugeki no Soma 2|Food Wars: Shokugeki no Soma 2|Shokugeki no Soma: The Second Plate
32542	Я — Сакамото, а что?	Sakamoto desu ga?	Haven't You Heard? I'm Sakamoto	Сакамото к вашим услугам|Меня зовут Сакамото, а что?|Сакамото
32615	Военная хроника маленькой девочки	Youjo Senki	Saga of Tanya the Evil	Сага о маленькой девочке: Таня — воплощение зла|The Military Chronicles of a Little Girl|Сага о Тане Злой|Таня Злая|Ёдзё Сэнки
32729	Орендж	Orange	Orange	
32867	Великий из бродячих псов 2	Bungou Stray Dogs 2nd Season	Bungo Stray Dogs 2	Бродячие псы: Литературные гении 2|Бродячие псы литературы 2
32901	Эроманга-сэнсэй	Eromanga-sensei	Eromanga Sensei	
32935	Волейбол!! 3	Haikyuu!! Karasuno Koukou vs. Shiratorizawa Gakuen Koukou	Haikyu!! 3rd Season	Haikyuu!! Third Season|Haikyuu!! Karasuno High VS Shiratorizawa Academy|Волейбол 3|Волейбол 3 сезон|Хайкю 3
32937	Этот замечательный мир! 2	Kono Subarashii Sekai ni Shukufuku wo! 2	KonoSuba: God's Blessing on This Wonderful World! 2	Богиня благословляет этот прекрасный мир 2|Этот прекрасный мир 2|Give Blessings to This Wonderful World! 2
32949	Тайные желания отвергнутых	Kuzu no Honkai	Scum's Wish	Кузу но Хонкай
32951	Хроники Акаши — худшего магического преподавателя	Rokudenashi Majutsu Koushi to Akashic Records	Akashic Records of Bastard Magic Instructor	Акашийские хроники худшего преподавателя магии|RokuAka
32995	Юри на льду	Yuri!!! on Ice	Yuri!!! On Ice	Юри на льду!!!|Юрий на льду
32998	91 день	91 Days	91 Days	
33049	Судьба/Ночь схватки: Прикосновение небес 2	Fate/stay night Movie: Heaven's Feel - II. Lost Butterfly	Fate/stay night: Heaven's Feel - II. Lost Butterfly	Fate/stay night Movie: Heaven's Feel 2
33050	Судьба/Ночь схватки: Прикосновение небес 3	Fate/stay night Movie: Heaven's Feel - III. Spring Song	Fate/stay night: Heaven's Feel - III. Spring Song	Fate/stay night Movie: Heaven's Feel 3
33206	Дракон-горничная госпожи Кобаяси	Kobayashi-san Chi no Maid Dragon	Miss Kobayashi's Dragon Maid	Кобаяши и её горничная-дракон|The maid dragon of Kobayashi-san|Дракон-горничная Кобаяси|Дракон горничная|Горничная дракон Кобаяши
33255	Ох уж этот экстрасенс Сайки Кусуо!	Saiki Kusuo no Ψ-nan	The Disastrous Life of Saiki K.	Несладкая жизнь псионика Сайки Кусуо|Saiki Kusuo no Psi Nan
33352	Вайолет Эвергарден	Violet Evergarden	Violet Evergarden	Виолетта Эвергарден|Вайолет Эвергарден 1 сезон
33486	Моя геройская академия 2	Boku no Hero Academia 2nd Season	My Hero Academia Season 2	Моя геройская академия 2 сезон
33487	Месть Масамунэ!	Masamune-kun no Revenge	Masamune-kun's Revenge	
33489	Академия ведьмочек	Little Witch Academia (TV)	Little Witch Academia	
33506	Синий экзорцист: Нечестивый король Киото	Ao no Exorcist: Kyoto Fujouou-hen	Blue Exorcist: Kyoto Saga	Blue Exorcist: Kyoto Impure King Arc
33674	Нет игры — нет жизни: Начало	No Game No Life: Zero	No Game, No Life: Zero	Без игры жизни нет: Начало|Игра на выживание: Начало|Без игры — нет жизни: Начало|Нет игры — нет жизни: Ноль|NGNL Zero|NGNL the Movie
34134	Ванпанчмен 2	One Punch Man 2nd Season	One-Punch Man Season 2	One Punch-Man 2|One-Punch Man 2|OPM 2|Ванпанчмен 2 сезон|Ван панч мен 2
34280	Геймеры!	Gamers!	Gamers!	
34437	Код Гиас: Лелуш Воскресший	Code Geass: Fukkatsu no Lelouch	Code Geass: Lelouch of the Re;surrection	Код Гиас: Воскресший Лелуш|Code Geass: Lelouch of the Resurrection
34542	Инуясики	Inuyashiki	Inuyashiki: Last Hero	Инуясики: Последний герой
34566	Боруто: Новое поколение Наруто	Boruto: Naruto Next Generations	Boruto: Naruto Next Generations	Боруто: Следующее поколение|Боруто|Боруто новое поколение
34572	Чёрный клевер	Black Clover	Black Clover	Черный клевер|Блэк Кловер
34577	Семь смертных грехов: Возрождение заповедей	Nanatsu no Taizai: Imashime no Fukkatsu	The Seven Deadly Sins: Revival of the Commandments	Семь смертных грехов 2
34599	Созданный в Бездне	Made in Abyss	Made in Abyss	Рождённый в Бездне|Сотворённый в Бездне|Сотворенный в Бездне|Мейд ин Абисс|Бездна
34612	Ох уж этот экстрасенс Сайки Кусуо! 2	Saiki Kusuo no Ψ-nan 2	The Disastrous Life of Saiki K. 2	Несладкая жизнь псионика Сайки Кусуо 2|Saiki Kusuo no Psi Nan 2
34618	Садистская смесь	Blend S	BLEND-S	
34798	Лагерь на свежем воздухе	Yuru Camp△	Laid-Back Camp	Девчачий кемпинг|Yurukyan|Юру Кэмп|Юру Камп
34902	Признания	Tsurezure Children	Tsuredure Children	Малолетние бездельники
34933	Безумный азарт	Kakegurui	Kakegurui	Маньяк ставок|Маньяк азартных игр|Какегуруи|Какэгуруи
34944	Великий из бродячих псов: Сгнившее яблоко	Bungou Stray Dogs: Dead Apple	Bungo Stray Dogs: Dead Apple	Великий из бродячих псов: Мёртвое яблоко|Бродячие псы: Литературные гении. Фильм|Бродячие псы литературы. Фильм
35062	Невеста чародея	Mahoutsukai no Yome	The Ancient Magus' Bride	The Magician's Bride|Mahoyome|Невеста колдуна
35073	Повелитель 2	Overlord II	Overlord II	Владыка 2
35120	Человек-дьявол: Плакса	Devilman: Crybaby	Devilman: Crybaby	Человек-дьявол: Плач|Человек дьявол плакса|Девилмен
35203	В другом мире со смартфоном	Isekai wa Smartphone to Tomo ni.	In Another World With My Smartphone	Со своим смартфоном в параллельном мире|In a Different World with a Smartphone.
35247	История финала 2	Owarimonogatari 2nd Season	Owarimonogatari Second Season	Финальные истории 2|Конец историй 2|История последствий 2|Истории конца 2|End Story 2nd Season|Оваримоногатари 2
35507	Добро пожаловать в класс превосходства	Youkoso Jitsuryoku Shijou Shugi no Kyoushitsu e	Classroom of the Elite	Добро пожаловать в класс элиты|Welcome to the Classroom of the Elite|Класс превосходства|Класс элиты|Добро пожаловать в класс для избранных
35608	Чудачества любви не помеха! Положись на меня	Chuunibyou demo Koi ga Shitai! Movie: Take On Me	Love, Chunibyo & Other Delusions!: Take On Me	Eiga Chuunibyou demo Koi ga Shitai! Take On Me
35760	Атака титанов 3	Shingeki no Kyojin Season 3	Attack on Titan Season 3	Вторжение гигантов 3|Атакующий титан 3|AoT 3|Атака титанов 3 сезон|Вторжение титанов 3
35788	Повар-боец Сома: Третье блюдо	Shokugeki no Souma: San no Sara	Food Wars! The Third Plate	В поисках божественного рецепта 3|Кулинарные поединки Сомы 3|Кухня Сомы 3|Shokugeki no Soma 3rd Season|Shokugeki no Soma 3
35790	Восхождение героя щита	Tate no Yuusha no Nariagari	The Rising of the Shield Hero	Становление героя щита|Герой щита|Восхождение героя щита 1 сезон
35839	Дальше, чем космос	Sora yori mo Tooi Basho	A Place Further Than The Universe	Место за вселенной|Место за пределами вселенной|Uchuu Yorimo Tooi Basho A Story That Leads to the Antarctica|Место дальше, чем Вселенная|Место дальше чем вселенная
35848	Промар	Promare	Promare	Промейр|Промэйр
35849	Милый во Франксе	Darling in the FranXX	DARLING in the FRANXX	Дарлинг ин зе Франкс|Любимый во Франксе|Франкс
35851	Укрась прощальное утро цветами обещания	Sayonara no Asa ni Yakusoku no Hana wo Kazarou	Maquia: When the Promised Flower Blooms	Let's Decorate the Promised Flowers in the Morning of Farewells|SayoAsa
35860	Озорная Такаги	Karakai Jouzu no Takagi-san	Teasing Master Takagi-san	Мастер дразнилок Такаги|Поддразнивание Такаги|Skilled Teaser Takagi-san|Такаги-сан|Такаги сан
35946	Семь смертных грехов: Узники небес	Nanatsu no Taizai Movie 1: Tenkuu no Torawarebito	The Seven Deadly Sins the Movie: Prisoners of the Sky	Семь смертных грехов: Небесный пленник|The Seven Deadly Sins Movie: Prisoners of the Sky
35968	Так сложно любить отаку	Wotaku ni Koi wa Muzukashii	Wotakoi: Love is Hard for Otaku	Очень трудно любить отаку|Любовь — проблема для отаку|Любовь и отаку|It's Difficult to Love an Otaku|WotaKoi|Love is Hard for Otaku
35994	Ангел кровопролития	Satsuriku no Tenshi	Angels of Death	Ангелы смерти|Angel of Massacre|Angel of Slaughter
36098	Я хочу съесть твою поджелудочную	Kimi no Suizou wo Tabetai	I Want To Eat Your Pancreas	Хочу съесть твою поджелудочную железу|Let Me Eat Your Pancreas|KimiSui|Хочу съесть твою поджелудочную|Поджелудочная
36286	Re:Zero. Жизнь с нуля в альтернативном мире: Снежные воспоминания	Re:Zero kara Hajimeru Isekai Seikatsu - Memory Snow	Re:ZERO -Starting Life in Another World- Memory Snow	Re: Life in a different world from zero|ReZero|Re:Zero kara Hajimeru Isekai Seikatsu OVA
36296	Праздник кукол	Hinamatsuri	Hinamatsuri	Хинамацури|Фестиваль кукол|Hina Festival
36407	Внук мудреца	Kenja no Mago	Wise Man's Grandchild	Philosopher's Grandson|Magi's Grandson
36456	Моя геройская академия 3	Boku no Hero Academia 3rd Season	My Hero Academia Season 3	Моя геройская академия 3 сезон
36474	Мастера Меча Онлайн: Алисизация	Sword Art Online: Alicization	Sword Art Online: Alicization	Искусство Меча Онлайн: Алисизация|Мастера Меча Онлайн 3|Sword Art Online III|SAO Alicization|Sword Art Online 3|SAO 3|Мастера меча онлайн: Алисизация|Мастера меча онлайн 3|САО 3
36475	Мастера Меча Онлайн: Альтернативная «Призрачная пуля»	Sword Art Online Alternative: Gun Gale Online		SAO Alternative Gun Gale Online
36491	Расколотая битвой синева небес	Doupo Cangqiong	Fights Break Sphere	Расколотая битвой синь небес|Battle Through the Heavens|Доупо Цанцюн
36511	Токийский гуль: Перерождение	Tokyo Ghoul:re	Tokyo Ghoul:re	Токийский монстр: Перерождение|Tokyo Kushu:re|Toukyou Kuushu:re|Токийский гуль 3|Токийский гуль ре
36862	Созданный в Бездне: Рассвет глубокой души	Made in Abyss Movie 3: Fukaki Tamashii no Reimei	Made in Abyss: Dawn of the Deep Soul	Рождённый в Бездне: Рассвет глубокой души
36882	Арифурэта: Сильнейший ремесленник в мире	Arifureta Shokugyou de Sekai Saikyou	Arifureta: From Commonplace to World's Strongest	От обычной работы до сильнейшего в мире|From Common Job Class to the Strongest in the World
36896	Моя геройская академия: Два героя	Boku no Hero Academia the Movie 1: Futari no Hero	My Hero Academia: Two Heroes	My Hero Academia the Movie: The Two Heroes
36946	Драконий жемчуг: Супер — Броли	Dragon Ball Super: Broly	Dragon Ball Super: Broly	
36949	Повар-боец Сома: Третье блюдо — Часть II	Shokugeki no Souma: San no Sara - Tootsuki Ressha-hen	Food Wars! The Third Plate: Totsuki Train Arc	Кухня Сомы 3 — Часть 2|Food Wars! The Third Plate 2nd cour|Shokugeki no Souma: San no Sara (2018)
37055	Военная хроника маленькой девочки. Фильм	Youjo Senki Movie	Saga of Tanya the Evil: The Movie	Gekijouban Youjo Senki
37086	Безумный азарт 2	Kakegurui××		Маньяк ставок 2|Маньяк азартных игр 2|Kakegurui 2nd Season|Kakegurui: Compulsive Gambler 2nd Season
37105	Необъятный океан	Grand Blue	Grand Blue Dreaming	Гранд Блю|Гранд Блу
37141	Клетки за работой	Hataraku Saibou	Cells at Work!	Работа клеток|Клетки на работе|Cells At Work|Клетки за работой!
37208	Магистр дьявольского культа	Mo Dao Zu Shi	The Master of Diabolism	Основатель тёмного пути|Неукротимый|Modao Zushi|Grandmaster of Demonic Cultivation|The Founder of Diabolism|The Founder of Evil Magic|Основатель дьявольского пути|Модао Цзуши
37210	Повелитель тьмы: Другая история мира — Магия подчинения	Isekai Maou to Shoukan Shoujo no Dorei Majutsu	How Not to Summon a Demon Lord	How NOT to Summon a Demon Lord
37347	Может, я встречу тебя в подземелье? 2	Dungeon ni Deai wo Motomeru no wa Machigatteiru Darou ka II	Is It Wrong to Try to Pick Up Girls in a Dungeon? II	Может, я встречу тебя в подземелье? Семейный миф|В подземелье я пойду, там красавицу найду 2|Неужели искать встречи в подземелье — неправильно? 2|DanMachi 2nd Season|Is It Wrong That I Want to Meet You in a Dungeon 2nd Season|Is It Wrong to Try to Pick Up Girls in a Dungeon? 2
37349	Убийца гоблинов	Goblin Slayer	Goblin Slayer	Гоблин Слеер|Гоблин Слэйер
37430	О моём перерождении в слизь	Tensei shitara Slime Datta Ken	That Time I Got Reincarnated as a Slime	Tensura|О моем перерождении в слизь|Тенсура|ТенСура|Слизь|Перерождение в слизь|Слайм
37450	Этот глупый свин не понимает мечту девочки-зайки	Seishun Buta Yarou wa Bunny Girl Senpai no Yume wo Minai	Rascal Does Not Dream of Bunny Girl Senpai	Эта глупая свинья не понимает мечту девочки-зайки!|Этот глупый свин|Глупый свин|Банни гёрл сэмпай|Девочка-зайка
37510	Моб Психо 100 2	Mob Psycho 100 II	Mob Psycho 100 II	Mob Psycho 100 2nd Season|Mob Psycho Hyaku|Mob Psycho One Hundred
37520	Дороро	Dororo	Dororo	Дороро и Хяккимару|Dororo to Hyakkimaru
37521	Сага о Винланде	Vinland Saga		Vinrando Saga|Винланд сага|Сага о Винланде 1 сезон
37675	Повелитель 3	Overlord III	Overlord III	Владыка 3
37779	Обещанный Неверленд	Yakusoku no Neverland	The Promised Neverland	Обещанная страна грёз|Обещанная страна грез|Обещанный Неверлэнд|Неверленд
37799	Токийский гуль: Перерождение 2	Tokyo Ghoul:re 2nd Season	Tokyo Ghoul:re 2nd Season	Токийский монстр: Перерождение 2|Tokyo Kushu:re|Toukyou Kuushu:re
37982	Домашняя подружка	Domestic na Kanojo	Domestic Girlfriend	Домашняя девушка|Девушка в моём доме|Домекано|Dome x Kano|Domekano|Домашняя подруга
37987	Вайолет Эвергарден. Фильм	Violet Evergarden Movie	Violet Evergarden: The Movie	Gekijouban Violet Evergarden
37991	Невероятное приключение ДжоДжо: Золотой ветер	JoJo no Kimyou na Bouken Part 5: Ougon no Kaze	JoJo's Bizarre Adventure: Golden Wind	JoJo's Bizarre Adventure Part 5: Golden Wind|Le Bizzarre Avventure Di GioGio Parte 5: Vento Aureo|ДжоДжо: Золотой ветер|Джоджо 5|Золотой ветер
37999	Госпожа Кагуя: в любви как на войне	Kaguya-sama wa Kokurasetai: Tensai-tachi no Renai Zunousen	Kaguya-sama: Love is War	Кагуя хочет, чтобы ей признались: Гении — Война любви и разума|Kaguya Wants to be Confessed To: The Geniuses' War of Love and Brains|Госпожа Кагуя: В любви как на войне|Госпожа Кагуя|Кагуя сама|Кагуя-сама|Кагуя
38000	Клинок, рассекающий демонов	Kimetsu no Yaiba	Demon Slayer: Kimetsu no Yaiba	Blade of Demon Destruction|Клинок рассекающий демонов|Истребитель демонов|Кимецу но Яйба|Демон Слеер|Демон Слэйер|Клинок демонов|Клинок рассекающий демонов 1 сезон
38003	Великий из бродячих псов 3	Bungou Stray Dogs 3rd Season	Bungo Stray Dogs 3	Бродячие псы: Литературные гении 3|Бродячие псы литературы 3
38040	Этот замечательный мир! Багровая легенда	Kono Subarashii Sekai ni Shukufuku wo! Movie: Kurenai Densetsu	KonoSuba: God's Blessing on This Wonderful World! - Legend of Crimson	Богиня благословляет этот прекрасный мир! Багровая легенда|KonoSuba Movie|Eiga Kono Subarashii Sekai ni Shukufuku wo!|Kono Subarashii Sekai ni Shukufuku wo! Movie
38101	Пять невест	5-toubun no Hanayome	The Quintessential Quintuplets	Gotoubun no Hanayome|The Five Wedded Brides|Квинтэссенция пяти невест|Невесты-пятерняшки
38329	Этот глупый свин не понимает мечту девочки-мечтательницы	Seishun Buta Yarou wa Yumemiru Shoujo no Yume wo Minai	Rascal Does Not Dream of a Dreaming Girl	Этот глупый свин не понимает мечту девочки-зайки. Фильм|Этот глупый свин не понимает мечту девочки из его снов|Негодник, которому не снилась девушка-кролик
38408	Моя геройская академия 4	Boku no Hero Academia 4th Season	My Hero Academia Season 4	Моя геройская академия 4 сезон
38414	Re:Zero. Жизнь с нуля в альтернативном мире: Замороженные узы	Re:Zero kara Hajimeru Isekai Seikatsu - Hyouketsu no Kizuna	Re:ZERO -Starting Life in Another World- The Frozen Bond	С нуля: пособие по выживанию в альтернативном мире — Ледяные узы|Re:ZERO: Starting Life in Another World - Frozen Bonds|Re:Zero kara Hajimeru Isekai Seikatsu OVA 2
38524	Атака титанов 3. Часть 2	Shingeki no Kyojin Season 3 Part 2	Attack on Titan Season 3 Part 2	Вторжение гигантов 3. Часть 2|Атакующий титан 3. Часть 2|Атака титанов 3 сезон часть 2
38659	Осторожный герой: и без того сильнейший, он слишком осторожен!	Shinchou Yuusha: Kono Yuusha ga Ore Tueee Kuse ni Shinchou Sugiru	Cautious Hero: The Hero Is Overpowered but Overly Cautious	Этот герой неуязвим, но очень осторожен|Этот герой чересчур осторожен, хоть и бессмертен|Kono Yuusha ga Ore Tueee Kuse ni Shinchou Sugiru|This Hero Is Invincible but "Too Cautious"
38668	Дорохедоро	Dorohedoro		Дорохэдоро
38671	Пламенная бригада пожарных	Enen no Shouboutai	Fire Force	Пожарная бригада|Бригада пылающего пламени|Огненная бригада пожарных|Fire Brigade of Flames|Пламенный отряд|Огненная бригада|Пожарная бригада пламени|Файр форс
38680	Корзинка фруктов (2019)	Fruits Basket 1st Season	Fruits Basket 1st Season	Фруктовая корзина|Furuba|Fruits Basket (Zenpen)
38691	Доктор Стоун	Dr. Stone	Dr. Stone	Доктор Камень|Др Стоун|Доктор Стоун 1 сезон
38759	Заботливая 800-летняя жена!	Sewayaki Kitsune no Senko-san	The Helpful Fox Senko-san	Непоседливая лисица Сэнко|800 с хвостиком!|Заботливая лисичка Сэнко|Заботливая лисица Сэнко|Заботливая лиса Сэнко|Meddlesome Kitsune Senko-san|Заботливая 800-летняя жена|Лисичка Сэнко|Сэнко-сан
38816	Здравствуй, мир	Hello World		Привет, мир
38826	Дитя погоды	Tenki no Ko	Weathering with You	Ребёнок погоды
38883	Волейбол!! К вершине	Haikyuu!! To the Top	Haikyu!! To the Top	Волейбол!! 4|Haikyuu!! (2020)|Haikyuu!! Fourth Season|Haikyuu!! 4th Season|Волейбол 4|Волейбол 4 сезон|Хайкю 4
39195	Выдающиеся звери	Beastars		Бистарс|Бистарз
39534	Туалетный мальчик Ханако	Jibaku Shounen Hanako-kun	Toilet-Bound Hanako-kun	
39535	Реинкарнация безработного: История о приключениях в другом мире	Mushoku Tensei: Isekai Ittara Honki Dasu	Mushoku Tensei: Jobless Reincarnation	Реинкарнация безработного|Мусёку Тэнсэй|Мушоку Тенсей|Реинкарнация безработного 1 сезон
39547	Как и ожидалось, моя школьная романтическая жизнь не удалась 3	Yahari Ore no Seishun Love Comedy wa Machigatteiru. Kan	My Teen Romantic Comedy SNAFU Climax!	Розовая пора моей школьной жизни — сплошной обман 3|Жизнь — любовное кино, но какое-то не то... 3|Как я и ожидал, моя школьная жизнь не задалась 3|Yahari Ore no Seishun Love Comedy wa Machigatteiru. 3rd Season|My Teen Romantic Comedy SNAFU 3|My youth romantic comedy is wrong as I expected 3|Oregairu 3
39551	О моём перерождении в слизь 2	Tensei shitara Slime Datta Ken 2nd Season	That Time I Got Reincarnated as a Slime Season 2	Tensura 2|О моем перерождении в слизь 2 сезон|Тенсура 2
39565	Моя геройская академия: Восхождение героев	Boku no Hero Academia the Movie 2: Heroes:Rising	My Hero Academia: Heroes Rising	Моя геройская академия: Восхождение героя|Моя геройская академия: Герои. Восстание|My Hero Academia the Movie 2: Heroes:Rising
39576	Убийца гоблинов: Корона гоблина	Goblin Slayer: Goblin's Crown	Goblin Slayer: Goblin's Crown	
39587	Re:Zero. Жизнь с нуля в альтернативном мире 2	Re:Zero kara Hajimeru Isekai Seikatsu 2nd Season	Re:ZERO -Starting Life in Another World- Season 2	С нуля: Пособие по выживанию в альтернативном мире 2|Re:Zero — жизнь с нуля в другом мире 2|Re: Life in a different world from zero 2nd Season|ReZero 2nd Season|Re:Zero - Starting Life in Another World 2
39597	Мастера Меча Онлайн: Алисизация — Война в Подмирье	Sword Art Online: Alicization - War of Underworld	Sword Art Online: Alicization - War of Underworld	Искусство Меча Онлайн: Алисизация — Война Андерворлда|Sword Art Online: Alicization 2nd Season|Sword Art Online III 2nd Season|SAO Alicization 2nd Season|Sword Art Online 3 2nd Season|SAO 3 2nd Season
39617	Обещанный Неверленд 2	Yakusoku no Neverland 2nd Season	The Promised Neverland Season 2	
39701	Семь смертных грехов: Гнев богов	Nanatsu no Taizai: Kamigami no Gekirin	The Seven Deadly Sins: Imperial Wrath of the Gods	The Seven Deadly Sins: Imperial Wrath of The Gods
39741	Вайолет Эвергарден: Вечность и призрак пера	Violet Evergarden Gaiden: Eien to Jidou Shuki Ningyou	Violet Evergarden: Eternity and the Auto Memory Doll	Вайолет Эвергарден: Вечность и автозапоминающая кукла|Violet Evergarden Side Story: Eternity and the Auto Memories Doll
39783	Пять невест 2	5-toubun no Hanayome ∬	The Quintessential Quintuplets 2	Gotoubun no Hanayome 2nd Season|The Five Wedded Brides 2nd Season|5-toubun no Hanayome 2nd Season|The Quintessential Quintuplets 2nd Season
39940	Повар-боец Сома: Четвёртое блюдо	Shokugeki no Souma: Shin no Sara	Food Wars! The Fourth Plate	Повар-боец Сома 4|Кулинарные поединки 4|Кулинарные поединки Сомы 4|В поисках божественного рецепта 4|Кухня Сомы 4|Shokugeki no Soma 4th Season
40028	Атака титанов: Финал	Shingeki no Kyojin: The Final Season	Attack on Titan: Final Season	Вторжение гигантов 4|Вторжение гигантов: Финал|Атака титанов 4|Атакующий титан 4|Атакующий титан: Финал|Shingeki no Kyojin Season 4|AoT 4|Атака титанов: Финальный сезон|Атака титанов 4 сезон|Атака титанов финал
40052	Великий притворщик	Great Pretender		Великий самозванец|Великий аферист
40060	Совершенно новый зверь	BNA	BNA: Brand New Animal	Совершенно новое животное|Зверь нового класса|Зверь нового типа|Brand New Animal|BNA: Совершенно новое животное|БНА
40221	Башня Бога	Kami no Tou	Tower of God	Sin-ui Tap|Тауэр оф Год
40356	Восхождение героя щита 2	Tate no Yuusha no Nariagari Season 2	The Rising of the Shield Hero Season 2	Становление героя щита 2
40454	Может, я встречу тебя в подземелье? 3	Dungeon ni Deai wo Motomeru no wa Machigatteiru Darou ka III	Is It Wrong to Try to Pick Up Girls in a Dungeon? III	В подземелье я пойду, там красавицу найду 3|Неужели искать встречи в подземелье — неправильно? 3|DanMachi 3rd Season|Is It Wrong That I Want to Meet You in a Dungeon 3rd Season
40456	Клинок, рассекающий демонов: Бесконечный поезд. Фильм	Kimetsu no Yaiba Movie: Mugen Ressha-hen	Demon Slayer: Kimetsu no Yaiba - The Movie: Mugen Train	Клинок, рассекающий демонов: Поезд бесконечных сновидений|Истребитель демонов: Бесконечный поезд|Gekijouban Kimetsu no Yaiba: Mugen Ressha-hen|Kimetsu no Yaiba: Infinity Train|Demon Slayer Movie: InfinityTrain|Клинок, рассекающий демонов: Бесконечный поезд|Клинок рассекающий демонов поезд|Бесконечный поезд
40496	Непризнанный школой владыка демонов! Сильнейший владыка демонов в истории поступает в академию, переродившись своим потомком	Maou Gakuin no Futekigousha: Shijou Saikyou no Maou no Shiso, Tensei shite Shison-tachi no Gakkou e Kayou	The Misfit of Demon King Academy	Это первый случай в истории колледжа дьявола|Непризнанный школой владыка демонов!
40540	Мастера Меча Онлайн: Алисизация — Война в Подмирье 2	Sword Art Online: Alicization - War of Underworld 2nd Season	Sword Art Online: Alicization - War of Underworld Part 2	Искусство Меча Онлайн: Алисизация — Война Андерворлда 2|Sword Art Online: Alicization 3rd Season|Sword Art Online III 3rd Season|SAO Alicization 3rd Season|Sword Art Online 3 3rd Season|SAO 3 3rd Season|SAO III 3rd Season
40591	Госпожа Кагуя: в любви как на войне 2	Kaguya-sama wa Kokurasetai? Tensai-tachi no Renai Zunousen	Kaguya-sama: Love is War?	Кагуя хочет, чтобы ей признались: Гении — Война любви и разума 2|Kaguya Wants to be Confessed To: The Geniuses' War of Love and Brains 2nd Season|Kaguya-sama wa Kokurasetai: Tensai-tachi no Renai Zunousen 2nd Season|Kaguya-sama: Love is War 2nd Season|Госпожа Кагуя 2|Госпожа Кагуя 2 сезон|Кагуя 2
40730	Благословение небожителей	Tian Guan Cifu	Heaven Official's Blessing	TGCF|Tian Guan Ci Fu|Tenkan Shifuku|Небожители
40748	Магическая битва	Jujutsu Kaisen	Jujutsu Kaisen	Sorcery Fight|JJK|Дзюдзюцу Кайсэн|Джуджуцу Кайсен|Джу-джуцу Кайсен|Магическая битва 1 сезон|Магическая битва 1
40776	Волейбол!! К вершине 2	Haikyuu!! To the Top Part 2	Haikyu!! To the Top 2nd-cour	Haikyu!! TO THE TOP 2nd-cour|Haikyu!! TO THE TOP Part 2
40787	Жозе, тигр и рыба	Josee to Tora to Sakana-tachi	Josee, the Tiger and the Fish	Джози, Тигр и Рыба
40834	Рейтинг короля	Ousama Ranking	Ranking of Kings	King Ranking|Рейтинг королей
40839	Девушка на час	Kanojo, Okarishimasu	Rent-a-Girlfriend	Девушка в аренду|Kanokari|Аренда девушки
40852	Доктор Стоун: Каменные войны	Dr. Stone: Stone Wars		Доктор Стоун 2|Dr. Stone 2nd Season|Dr. Stone Second Season
40938	Я побрился. Затем привёл домой старшеклассницу	Hige wo Soru. Soshite Joshikousei wo Hirou.	Higehiro: After Being Rejected, I Shaved and Took in a High School Runaway	Я напился. Затем привёл домой старшеклассницу|I Shaved. Then I Brought a High School Girl Home.|Higehiro
40956	Пламенная бригада пожарных: Вторая глава	Enen no Shouboutai: Ni no Shou	Fire Force Season 2	Пожарная бригада 2|Бригада пылающего пламени 2|Огненная бригада пожарных 2|Enen no Shouboutai 2nd Season|Fire Force 2nd Season
41025	Для тебя, Бессмертный	Fumetsu no Anata e	To Your Eternity	To You, the Immortal|Your Immortal Self|Для тебя бессмертный|Фуметсу но Аната э
41353	Бог старшей школы	The God of High School	The God of High School	Царь горы|GOHS
41389	Унеси меня на Луну	Tonikaku Kawaii	Tonikawa: Over The Moon For You	Generally Cute|Fly Me to the Moon
41457	Восемьдесят шесть	86	86 Eighty-Six	Eighty Six|86 Эйти-Сикс|Эйти сикс
41467	Блич: Тысячелетняя кровавая война	Bleach: Sennen Kessen-hen	Bleach: Thousand-Year Blood War	Блич 2|Bleach: Thousand-Year Blood War Arc|Блич тысячелетняя война|Блич 2022
41487	О моём перерождении в слизь 2. Часть 2	Tensei shitara Slime Datta Ken 2nd Season Part 2	That Time I Got Reincarnated as a Slime Season 2 Part 2	Tensura 2
41587	Моя геройская академия 5	Boku no Hero Academia 5th Season	My Hero Academia Season 5	My Hero Academia 5
42203	Re:Zero. Жизнь с нуля в альтернативном мире 2. Часть 2	Re:Zero kara Hajimeru Isekai Seikatsu 2nd Season Part 2	Re:ZERO -Starting Life in Another World- Season 2 Part 2	С нуля: Пособие по выживанию в альтернативном мире 2. Часть 2|Re:Zero — жизнь с нуля в другом мире 2. Часть 2|Re: Life in a different world from zero 2nd Season|ReZero 2nd Season|Re:Zero - Starting Life in Another World 2|Re:Zero. Жизнь с нуля в альтернативном мире 2|Ре Зеро 2|Ре Зеро 2 сезон
42249	Токийские мстители	Tokyo Revengers	Tokyo Revengers	Токио ревенджерс|Токийские мстители 1 сезон
42310	Киберпанк: Бегущие по краю	Cyberpunk: Edgerunners		Киберпанк бегущие по краю|Киберпанк Эджраннерс|Киберпанк
42361	Не издевайся, Нагаторо	Ijiranaide, Nagatoro-san	Don't Toy with Me, Miss Nagatoro	Нагаторо, хватит издеваться!|Please don't bully me, Nagatoro|Не издевайся Нагаторо|Нагаторо|Нагаторо-сан
42897	Хоримия	Horimiya	Horimiya	Hori-san and Miyamura-kun
42916	Мастера Меча Онлайн: Прогрессив — Ария в беззвёздной ночи	Sword Art Online: Progressive Movie - Hoshi Naki Yoru no Aria	Sword Art Online the Movie: Progressive - Aria of a Starless Night	Искусство Меча Онлайн: Прогрессив — Ария в беззвёздной ночи|SAO Progressive Movie|Aria in the Starless Night|Hoshinaki Yoru no Aria
42923	Скейт: Бесконечность	SK∞	SK8 the Infinity	SK Eight|Skate
43299	Приоритет чудо-яйца	Wonder Egg Priority	Wonder Egg Priority	
43608	Госпожа Кагуя: в любви как на войне 3	Kaguya-sama wa Kokurasetai: Ultra Romantic	Kaguya-sama: Love is War -Ultra Romantic-	Кагуя хочет, чтобы ей признались: Гении — Война любви и разума 3|Госпожа Кагуя: в любви как на войне. Ультраромантика|Kaguya Wants to be Confessed To: The Geniuses' War of Love and Brains 3rd Season|Kaguya-sama wa Kokurasetai: Tensai-tachi no Renai Zunousen 3rd Season|Kaguya-sama: Love is War 3rd Season
44200	Моя геройская академия: Миссия мировых героев	Boku no Hero Academia the Movie 3: World Heroes' Mission	My Hero Academia: World Heroes' Mission	My Hero Academia the Movie 3
44511	Человек-бензопила	Chainsaw Man	Chainsaw Man	CSM|Человек бензопила|Чейнсо мен|Чейнсоумен|Бензопила
45576	Реинкарнация безработного: История о приключениях в другом мире. Часть 2	Mushoku Tensei: Isekai Ittara Honki Dasu Part 2	Mushoku Tensei: Jobless Reincarnation Part 2	Jobless Reincarnation Season 1 Part 2
45613	Моя девушка не только милая	Kawaii dake ja Nai Shikimori-san	Shikimori's Not Just a Cutie	Моя девушка не просто милая|Моя девушка совсем не милая|Госпожа Сикимори совсем не милая|Miss Shikimori is not just cute|That Girl Is Not Just Cute
46569	Адский рай	Jigokuraku	Hell's Paradise	Paradition|Heavenhell|Дзигокураку|Хэллс Парадайз
47194	Летнее время	Summertime Render	Summer Time Rendering	Саммер Тайм Рендеринг|Саммертайм рендер
47778	Клинок, рассекающий демонов: Квартал красных фонарей	Kimetsu no Yaiba: Yuukaku-hen	Demon Slayer: Kimetsu no Yaiba Entertainment District Arc	Клинок рассекающий демонов квартал красных фонарей|Клинок рассекающий демонов 2 сезон
47790	Лучший в мире ассасин, переродившийся в другом мире как аристократ	Sekai Saikou no Ansatsusha, Isekai Kizoku ni Tensei suru	The World's Finest Assassin Gets Reincarnated in Another World as an Aristocrat	Лучший в мире убийца, переродившийся в другом мире как аристократ|Лучший ассасин, переродившийся аристократом|The world's best assassin|To reincarnate in a different world aristocrat|Ansatsu Kizoku
47917	Одинокий рокер!	Bocchi the Rock!	Bocchi the Rock!	Рок-тихоня!|Одинокий рокер|Боччи зе рок|Бочи рок
48316	Восхождение в тени!	Kage no Jitsuryokusha ni Naritakute!	The Eminence in Shadow	Быть силой в тени!|To Be a Power in the Shadows!
48548	Пять невест. Фильм	5-toubun no Hanayome Movie	The Quintessential Quintuplets Movie	Gotoubun no Hanayome Movie|The Five Wedded Brides Movie
48561	Магическая битва 0. Фильм	Jujutsu Kaisen 0 Movie	Jujutsu Kaisen 0	Gekijouban Jujutsu Kaisen 0|JJK 0|Магическая битва 0|Магическая битва: Фильм|Магическая битва ноль
48569	Восемьдесят шесть. Часть 2	86 Part 2	86 Eighty-Six Part 2	Eighty Six 2nd Season
48580	Мемуары Ванитаса	Vanitas no Karte	The Case Study of Vanitas	Vanitas no Carte|Memoir of Vanitas|Vanitas no Shuki
48583	Атака титанов: Финал. Часть 2	Shingeki no Kyojin: The Final Season Part 2	Attack on Titan: Final Season Part 2	Вторжение гигантов 4. Часть 2|Вторжение гигантов: Финал. Часть 2|Атака титанов 4. Часть 2|Атакующий титан 4. Часть 2|Атакующий титан: Финал. Часть 2|Shingeki no Kyojin Season 4|Attack on Titan Season 4|Атака титанов: Финальный сезон часть 2|Атака титанов 4 сезон 2 часть
48661	Невероятное приключение ДжоДжо: Каменный океан	JoJo no Kimyou na Bouken Part 6: Stone Ocean	JoJo's Bizarre Adventure: Stone Ocean	JoJo's Bizarre Adventure Part 6: Stone Ocean
48736	Эта фарфоровая кукла влюбилась	Sono Bisque Doll wa Koi wo Suru	My Dress-Up Darling	Sono Kisekae Ningyou wa Koi wo Suru|KiseKoi|Фарфоровая кукла|Соно Бисуку Дору|Марин Китагава
48895	Повелитель 4	Overlord IV	Overlord IV	Владыка 4
48926	У Коми проблемы с общением	Komi-san wa, Comyushou desu.	Komi Can't Communicate	Komi-san Has a Communication Disorder.|Komi-san wa, Communication Shougai desu.|Komi-san wa, Komyushou Desu.|Коми сан|Коми-сан|Коми не может общаться
49387	Сага о Винланде 2	Vinland Saga Season 2	Vinland Saga Season 2	Vinrando Saga 2|Сага о Винланде 2 сезон
49596	Синяя тюрьма: Блю Лок	Blue Lock	Blue Lock	Синяя тюрьма|Блю Лок|Блю лок|Синяя тюрьма 1 сезон
49918	Моя геройская академия 6	Boku no Hero Academia 6th Season	My Hero Academia Season 6	My Hero Academia 6
49926	Клинок, рассекающий демонов: Бесконечный поезд	Kimetsu no Yaiba: Mugen Ressha-hen	Demon Slayer: Kimetsu no Yaiba Mugen Train Arc	Kimetsu no Yaiba Movie: Mugen Ressha-hen (TV)
50172	Моб Психо 100 3	Mob Psycho 100 III	Mob Psycho 100 III	Mob Psycho 100 3rd Season|Mob Psycho Hyaku|Mob Psycho One Hundred|Моб Психо 100 3 сезон
50265	Семья шпиона	Spy x Family		Спай Фэмили|Шпион семья|Семья шпиона 1 сезон
50346	Песнь ночных сов	Yofukashi no Uta	Call of the Night	Песня ночных бродяг|Пение полуночной совы|Зов ночи|Песня ночных сов
50594	Судзумэ, закрывающая двери	Suzume no Tojimari	Suzume	Воробей из замочной скважины|Судзумэ закрывает двери|Судзумэ захлопывает двери|Судзумэ запирает двери|Suzume's Locking-Up
50602	Семья шпиона. Часть 2	Spy x Family Part 2		
50709	Ликорис Рикоил	Lycoris Recoil	Lycoris Recoil	Ликорис Рекойл|LycoReco|Ликорис
51009	Магическая битва 2	Jujutsu Kaisen 2nd Season	Jujutsu Kaisen Season 2	Jujutsu Kaisen: Kaigyoku Gyokusetsu|Jujutsu Kaisen: Shibuya Jihen|Jujutsu Kaisen: Hidden Inventory Arc|Jujutsu Kaisen: Shibuya Incident Arc|Sorcery Fight|JJK|Магическая битва 2 сезон|Магическая битва второй сезон
51019	Клинок, рассекающий демонов: Деревня кузнецов	Kimetsu no Yaiba: Katanakaji no Sato-hen	Demon Slayer: Kimetsu no Yaiba Swordsmith Village Arc	Истребитель демонов: Деревня кузнецов|Клинок рассекающий демонов деревня кузнецов|Клинок рассекающий демонов 3 сезон
51096	Добро пожаловать в класс превосходства 2	Youkoso Jitsuryoku Shijou Shugi no Kyoushitsu e 2nd Season	Classroom of the Elite II	Добро пожаловать в класс для особо одарённых 2|Добро пожаловать в класс элиты 2|Classroom of the Elite 2nd Season|You-zitsu
51179	Реинкарнация безработного: История о приключениях в другом мире 2	Mushoku Tensei II: Isekai Ittara Honki Dasu	Mushoku Tensei: Jobless Reincarnation Season 2	Mushoku Tensei: Перерождение безработного 2|Jobless Reincarnation: I Will Seriously Try If I Go To Another World|Mushoku Tensei: Isekai Ittara Honki Dasu 2nd Season|Реинкарнация безработного 2|Реинкарнация безработного 2 сезон
51535	Атака титанов: Финал — Заключительная глава	Shingeki no Kyojin: The Final Season - Kanketsu-hen	Attack on Titan: Final Season - The Final Chapters	Вторжение гигантов: Финал — Заключительная глава|Атакующий титан: Финал — Заключительная глава|Shingeki no Kyojin: The Final Season Part 3|Shingeki no Kyojin Season 4|Attack on Titan Season 4|Атака титанов: Финальный сезон часть 3|Атака титанов: Финальные главы|Атака титанов финал
52034	Ребёнок идола	[Oshi no Ko]	[Oshi No Ko]	Ребёнок айдола|My Star|Звёздное дитя|Звездное дитя|Оси но Ко|Оши но Ко|Любимый ребёнок|Моя любимая звезда
52198	Госпожа Кагуя: в любви как на войне — Первый поцелуй никогда не заканчивается	Kaguya-sama wa Kokurasetai: First Kiss wa Owaranai	Kaguya-sama: Love is War -The First Kiss That Never Ends-	Госпожа Кагуя: в любви как на войне. Бесконечный первый поцелуй|Госпожа Кагуя: Первый поцелуй не кончается|Кагуя первый поцелуй
52211	Магия и мускулы	Mashle	Mashle: Magic and Muscles	MASHLE: Магия и мускулы|Машл|Мэшл|Мэшл: Магия и мускулы|Машл магия и мускулы
52299	Поднятие уровня в одиночку	Ore dake Level Up na Ken	Solo Leveling	I Level Up Alone|Na Honjaman Level Up|Соло Левелинг|Соло левелинг|Поднятие уровня|Поднятие уровня в одиночку 1 сезон
52588	Кайдзю номер восемь	Kaijuu 8-gou	Kaiju No. 8	8Kaijuu|Monster #8|Kaiju No. Eight|Kaiju #8|Кайдзю № 8|Кайдзю номер 8|Монстр №8|Кайдзю 8
52991	Провожающая в последний путь Фрирен	Sousou no Frieren	Frieren: Beyond Journey's End	Фрирен, провожающая в последний путь|Frieren at the Funeral|Фрирен|Фрирен провожающая в последний путь|Фририн
53393	Иллюзия рая	Tengoku Daimakyou	Heavenly Delusion	Великая небесная стена|Иллюзия небес
53887	Семья шпиона 2	Spy x Family Season 2		
54112	Предсмертный список зомби	Zom 100: Zombie ni Naru made ni Shitai 100 no Koto	Zom 100: Bucket List of the Dead	Зомби-апокалипсис и сто предсмертных дел|Зомби-апокалипсис и список из ста дел, что я выполню перед смертью|Bucket List of The Dead|Zombie 100: 100 Things I Want to do Before I Become a Zombie
54492	Монолог фармацевта	Kusuriya no Hitorigoto	The Apothecary Diaries	Записки аптекаря|Монолог аптекаря|Drugstore Soliloquy|Дневник аптекаря|Монолог травницы|Аптекарь
55701	Клинок, рассекающий демонов: Тренировка столпов	Kimetsu no Yaiba: Hashira Geiko-hen	Demon Slayer: Kimetsu no Yaiba Hashira Training Arc	Клинок, рассекающий демонов: Тренировки со столпами|Истребитель демонов: Тренировка столпов|Истребитель демонов: На тренировку столпов|Клинок рассекающий демонов тренировка столпов|Клинок рассекающий демонов 4 сезон
57334	Дандадан	Dandadan	Dan Da Dan	Дан да дан|Дэндэдэн
57555	Человек-бензопила: Резе	Chainsaw Man Movie: Reze-hen	Chainsaw Man – The Movie: Reze Arc	Человек-бензопила: История Резе|Gekijouban Chainsaw Man: Reze-hen
58567	Поднятие уровня в одиночку 2: Восстаньте из тени	Ore dake Level Up na Ken Season 2: Arise from the Shadow	Solo Leveling Season 2: Arise from the Shadow	Solo Leveling Second Season|Поднятие уровня в одиночку 2|Поднятие уровня в одиночку 2 сезон|Соло Левелинг 2
59192	Клинок, рассекающий демонов: Бесконечный замок — Возвращение Акадзы	Kimetsu no Yaiba Movie 1: Mugenjou-hen - Akaza Sairai	Demon Slayer: Kimetsu no Yaiba Infinity Castle I	Клинок, рассекающий демонов: Бесконечный замок|Клинок, рассекающий демонов: Бесконечная крепость|Истребитель демонов: Крепость бесконечности|Истребитель демонов: Бесконечная крепость
"""
}
