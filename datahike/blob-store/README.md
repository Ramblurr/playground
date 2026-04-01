# blob-store

Example of using Datahike as the system of record and Konserve as a blob store for large strings.

- Datahike stores document metadata and a blob key.
- Konserve stores the large string body.
- The query loads the body directly in the query with `konserve.core/get` inside `:where`.

Run:

```bash
clojure -M:run
```
