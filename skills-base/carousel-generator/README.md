# Carousel Generator

Генерация каруселей для Instagram и LinkedIn локально, через Claude Code. Без подписок, без Canva, без дизайнера.

Скачиваешь архив → кладёшь папку → говоришь Claude Code «разберись» → он настраивает всё под твой бренд и генерирует карусели по запросу.

## Что внутри

```
carousel-generator/
├── SKILL.md              # Инструкция для Claude Code (срабатывает по триггерам)
├── README.md             # Этот файл
├── BRAND.example.md      # Темплейт брендбука. Копируешь в BRAND.md и заполняешь
├── _render-core.js       # Ядро рендера (шрифты, ассеты, плейсхолдеры)
├── generate.js           # data.json → PNG через Puppeteer
├── preview.js            # data.json → HTML-галерея для ревью
├── package.json          # Зависимости (только puppeteer)
├── fonts.config.json     # Список шрифтов (заполняешь под свои)
├── templates/
│   └── simple.html       # Минимальный стартовый шаблон
├── fonts/                # Сюда кладёшь .ttf/.otf файлы
├── assets/               # Сюда кладёшь SVG/PNG иконки
└── carousels/
    └── example/
        └── data.json     # Рабочий пример на 3 слайда
```

## Установка

### 1. Положи папку
Распакуй архив в удобное место. Например, `~/Carousels/` или `C:/Carousels/`.

### 2. Поставь зависимости

```bash
cd carousel-generator
npm install
npx puppeteer browsers install chrome
```

Первая команда ставит Puppeteer. Вторая один раз качает Chromium (~200MB), который Puppeteer использует для рендера.

### 3. Проверь, что работает

```bash
node generate.js example
```

Должен появиться `output/example/slide-01.png` и ещё два слайда. Если открывается — всё ок.

### 4. Передай проект Claude Code

Открой папку в Claude Code и напиши:

```
Разберись с этим проектом. Я хочу генерировать карусели
для Instagram/LinkedIn в своём стиле. Помоги настроить
под мой бренд: цвета, шрифты, первый шаблон.
```

Claude Code прочитает `SKILL.md`, `README.md`, задаст вопросы про бренд и поможет заполнить `BRAND.md`, добавить шрифты, адаптировать шаблон.

## Использование

После настройки просто говоришь в Claude Code:

> Создай карусель на тему «5 ошибок начинающих копирайтеров»

Claude Code:
1. Читает `BRAND.md`, смотрит твой шаблон
2. Смотрит предыдущие карусели, чтобы новая отличалась визуально
3. Создаёт `carousels/<slug>/data.json`
4. Запускает `node preview.js <slug>` → в браузере открывается галерея для ревью
5. Ты говоришь правки («укороти заголовок второго слайда», «замени иконку»)
6. Клод правит, перезапускает preview
7. Когда одобряешь — запускает `node generate.js <slug>` → финальные PNG в `output/<slug>/`

## Как Claude Code адаптирует шаблон под тебя

Стартовый `templates/simple.html` это чистый минимум: белый фон, чёрный текст, синий акцент. Это задумано так, чтобы ты мог попросить Claude:

> Сделай мой шаблон: тёмный фон, неоновый зелёный акцент, заголовки в Monument Extended, плавающие геометрические декорации в углах.

Клод прочитает `simple.html`, поймёт структуру (поля `body`, `decor`, footer) и сделает тебе новый шаблон по бренду. Хранишь столько шаблонов, сколько нужно — в `templates/`.

## Структура data.json

```json
{
  "config": {
    "template": "simple",
    "cta": "→",
    "width": 1080,
    "height": 1350
  },
  "slides": [
    {
      "decor": "<опциональные декорации>",
      "body": "<HTML со содержимым слайда>"
    }
  ]
}
```

- `template` — имя шаблона из `templates/` без `.html`
- `cta` — текст в футере (стрелка, «swipe», твой текст)
- `slides[].body` — HTML контента, использует CSS-классы шаблона
- `slides[].decor` — декоративный слой поверх фона
- `{{asset:filename.svg}}` — ссылка на файл из `assets/`
- `{{slideNumber}}` и `{{totalSlides}}` — подставляются рендером

## Шрифты

Положи `.ttf`/`.otf` в `fonts/` и опиши в `fonts.config.json`:

```json
[
  { "family": "Inter", "weight": "400 700", "file": "Inter-Variable.ttf" }
]
```

Без этого шаг шаблон использует системные шрифты (Inter / system-ui).

## Требования

- **Node.js 20+**
- **Claude Code** (desktop или CLI)
- ~200MB свободно (для Chromium, который качает Puppeteer)
- Windows / macOS / Linux — работает везде

## Советы

- Начни с `carousels/example/` — получи первый PNG, чтобы увидеть, как всё устроено.
- Заполни `BRAND.md` до того, как начнёшь серьёзно генерить. Без брендбука карусели будут разнородные.
- Не правь `_render-core.js` без нужды. Это ядро, оно универсальное.
- Шаблонов может быть много: `templates/cover-hero.html`, `templates/tutorial.html`, `templates/quote.html` — просто указываешь нужный в `config.template`.
- Каждая карусель в отдельной папке в `carousels/` — не смешивай темы.

## Откуда это

Скилл сделан Никитой Ефимовым. Полный разбор и видео-демонстрация: **[impact.life](https://impact.life)**.

Если хочешь разобраться глубже в Claude Code: [impact.life/guide](https://impact.life/guide).
