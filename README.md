# Open WebUI + SearXNG (чат + web search)

Самый простой стенд с Open WebUI, Ollama и SearXNG, чтобы работал веб‑поиск с JSON‑ответом.

## Быстрый старт

```bash
docker-compose up -d
```

После запуска:
- Open WebUI: <http://localhost:3000>
- SearXNG (если нужно проверить вручную): <http://localhost:8888>

## Важные детали про JSON в SearXNG

Open WebUI ожидает переменную `SEARXNG_QUERY_URL` с плейсхолдером `<query>` и JSON‑ответом. В этом проекте она уже настроена так:

```
http://searxng:8080/search?q=<query>&format=json
```

Чтобы JSON работал, он **должен быть разрешён** в `settings.yml` SearXNG, иначе будет `403 Forbidden`. В файле `searxng/settings.yml` это включено через `search.formats`.

## Что нужно поменять под себя

- `WEBUI_SECRET_KEY` в `docker-compose.yml`
- `server.secret_key` в `searxng/settings.yml`

## Примечания

- Ollama включена как базовая LLM‑runtime для Open WebUI (порт `11434`).
- Если у вас уже есть внешний Ollama, можно убрать сервис `ollama` и заменить `OLLAMA_BASE_URL` на ваш адрес.

## Модели пользователя

Для вашей конфигурации:
- LLM: `MFDoom/deepseek-r1-tool-calling:8b`
- Embeddings: `nomic-embed-text:latest`

Их можно загрузить в Ollama после старта:

```bash
ollama pull MFDoom/deepseek-r1-tool-calling:8b
ollama pull nomic-embed-text:latest
```
