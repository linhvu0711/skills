# Preset: effect

| key | value |
| --- | --- |
| package | effect |
| repo | https://github.com/Effect-TS/effect.git |
| ref | effect@{version} |
| version_file | packages/effect/package.json |

Tags look like `effect@3.14.0`. The sub-packages (`@effect/platform`, `@effect/sql`, `@effect/ai`) ship from the same monorepo, so one clone covers them all. The ref follows the core `effect` version; a sub-package that lags its installed version by a patch or two is fine.

## Where the good examples live

Tests show real usage; the docs are written for people.

| topic | read first |
| --- | --- |
| Schema | `packages/effect/test/Schema/` and `packages/effect/src/Schema.ts` header comments |
| services and layers | `packages/effect/test/Layer.test.ts`, `packages/effect/test/Context.test.ts` |
| errors | `packages/effect/test/Cause.test.ts`, `packages/effect/src/Data.ts` (`TaggedError`) |
| config | `packages/effect/test/Config.test.ts` |
| HTTP and platform | `packages/platform/test/`, `packages/platform-node/test/` |
| SQL | `packages/sql/test/`, `packages/sql-pg/test/` |
| testing | `packages/vitest/`, any `*.test.ts` under `packages/effect/test/` |

## Idiom files to generate

Write these four by default. Add `effect-platform.md` or `effect-sql.md` only when the project already depends on `@effect/platform` or `@effect/sql`.

- `docs/idioms/effect-schema.md`: `Schema.Struct`, `Schema.Class`, `Schema.decodeUnknown`, transforms, filters, `Schema.TaggedError`.
- `docs/idioms/effect-services.md`: `Context.Tag` and `Effect.Service`, `Layer.succeed`/`Layer.effect`, composing with `Layer.provide`, test layers.
- `docs/idioms/effect-errors.md`: `Data.TaggedError`, `Effect.catchTag`, `Effect.catchTags`, typed error channel, `Effect.mapError`.
- `docs/idioms/effect-config.md`: `Config.string`, `Config.nested`, `Config.withDefault`, `ConfigProvider` for tests.
