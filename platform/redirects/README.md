# Legacy redirects

These Caddyfiles map old product hosts to canonical Regents URLs. Browser reads
use 301. Requests other than GET and HEAD use 308 so the client keeps its
method. Agents must sign the new URL directly for audience `regents`.
Connected apps approve a new OAuth connection at `https://regents.sh/mcp`.

Keyfleet's Caddyfile keeps the notebook hub's public JWK Set available at the
old issuer URL. It reads the current keys from Regents. The legacy Keyfleet Fly
app's platform configuration includes distinct website and graph process groups.
Apply this Caddyfile only to the website redirector after confirming that process
mapping. The other redirectors' single-process Fly configurations are unsuitable
for this app.
