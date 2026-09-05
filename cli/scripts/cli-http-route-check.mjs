import fs from "node:fs";
import path from "node:path";

const HTTP_METHODS = new Set(["GET", "PUT", "POST", "DELETE", "OPTIONS", "HEAD", "PATCH", "TRACE"]);

const stripStringDelimiters = (input) => input.slice(1, -1);

const normalizeRouteShape = (input) => {
  const withoutQuery = input.split("?")[0] ?? input;
  return withoutQuery
    .replaceAll(/`/g, "")
    .replaceAll(/^\s*["']|["']\s*$/g, "")
    .replaceAll(/\$\{[^}]+\}/g, "{}")
    .replaceAll(/\{[^}/]+\}/g, "{}")
    .replaceAll(/\/+/g, "/");
};

const probableOwner = (routeShape) => {
  if (routeShape.startsWith("/api/autolaunch/")) return "autolaunch";
  if (routeShape.startsWith("/api/techtree/")) return "techtree";
  if (routeShape.startsWith("/api/platform/")) return "platform";
  if (routeShape.startsWith("/api/shared/identity/") || routeShape.startsWith("/api/shared/siwa/")) {
    return "shared-services";
  }
  if (routeShape.startsWith("/api/shared/")) return "platform";
  return "unknown";
};

const parseOpenApiMethodIndex = (owner, file, YAML) => {
  const document = YAML.parse(fs.readFileSync(file, "utf8"));
  const entries = [];

  for (const [routePath, methods] of Object.entries(document.paths ?? {})) {
    if (!methods || typeof methods !== "object") {
      continue;
    }

    const routeShape = normalizeRouteShape(routePath);
    for (const [method, operation] of Object.entries(methods)) {
      const normalizedMethod = method.toUpperCase();
      if (!HTTP_METHODS.has(normalizedMethod)) {
        continue;
      }

      entries.push({
        owner,
        file,
        method: normalizedMethod,
        routePath,
        routeShape,
        operationId:
          operation && typeof operation === "object" && typeof operation.operationId === "string"
            ? operation.operationId
            : null,
      });
    }
  }

  return entries;
};

const readFilesRecursively = (dir, predicate) =>
  fs
    .readdirSync(dir, { withFileTypes: true })
    .flatMap((entry) => {
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        return readFilesRecursively(fullPath, predicate);
      }
      return entry.isFile() && predicate(fullPath) ? [{ path: fullPath, source: fs.readFileSync(fullPath, "utf8") }] : [];
    });

export const readRouteCommandHandlers = (routeSources) => {
  const handlers = new Map();
  const routeEntryPattern =
    /(?:"([^"]+)"|([A-Za-z][\w-]*))\s*:\s*\{\s*run:\s*(?:\(\s*\{[\s\S]*?\}\s*\)\s*=>\s*)?([A-Za-z]\w+)\s*\(/g;

  for (const source of routeSources) {
    for (const match of source.matchAll(routeEntryPattern)) {
      handlers.set(match[1] ?? match[2], match[3]);
    }
  }

  return handlers;
};

const findMatchingBrace = (source, openBraceIndex) => {
  let depth = 0;
  let quote = null;
  let escaped = false;

  for (let index = openBraceIndex; index < source.length; index += 1) {
    const char = source[index];

    if (quote) {
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char === "\\") {
        escaped = true;
        continue;
      }
      if (char === quote) {
        quote = null;
      }
      continue;
    }

    if (char === "\"" || char === "'" || char === "`") {
      quote = char;
      continue;
    }

    if (char === "{") {
      depth += 1;
    } else if (char === "}") {
      depth -= 1;
      if (depth === 0) {
        return index;
      }
    }
  }

  return -1;
};

export const readExportedFunctionBodies = (commandSources) => {
  const functions = new Map();

  for (const { path: filePath, source } of commandSources) {
    const declarationPattern = /export\s+async\s+function\s+([A-Za-z]\w*)\s*\(/g;
    for (const match of source.matchAll(declarationPattern)) {
      const openBraceIndex = source.indexOf("{", match.index);
      if (openBraceIndex < 0) {
        continue;
      }
      const closeBraceIndex = findMatchingBrace(source, openBraceIndex);
      if (closeBraceIndex < 0) {
        continue;
      }
      functions.set(match[1], {
        filePath,
        body: source.slice(openBraceIndex, closeBraceIndex + 1),
      });
    }
  }

  return functions;
};

const stringLiteralPattern = "(?:`[^`]*?/api/[^`]*?`|\"[^\"]*?/api/[^\"]*?\"|'[^']*?/api/[^']*?')";

export const collectHttpOperationsFromFunctionBody = (body) => {
  const operations = [];
  const add = (method, literal) => {
    const rawPath = stripStringDelimiters(literal);
    const routeShape = normalizeRouteShape(rawPath);
    if (!routeShape.startsWith("/api/")) {
      return;
    }

    operations.push({ method, rawPath, routeShape });
  };

  const methodFirstPattern = new RegExp(
    `(?:requestJson|requestTypedJson|requestProductJson|requestStakingJson)(?:<[^)]*?>)?\\(\\s*["'](${Array.from(HTTP_METHODS).join("|")})["']\\s*,\\s*(${stringLiteralPattern})`,
    "g",
  );
  for (const match of body.matchAll(methodFirstPattern)) {
    add(match[1], match[2]);
  }

  const getFirstPattern = new RegExp(`(?:fetchTechtreeJson)\\(\\s*(${stringLiteralPattern})`, "g");
  for (const match of body.matchAll(getFirstPattern)) {
    add("GET", match[1]);
  }

  const preparedActionPattern = new RegExp(`prepareOrSubmitWalletAction\\(\\s*(${stringLiteralPattern})`, "g");
  for (const match of body.matchAll(preparedActionPattern)) {
    add("POST", match[1]);
  }

  const platformSessionPattern = /requestPlatformSessionJson\(\s*\{([\s\S]*?)\n\s*\}\s*\)/g;
  for (const match of body.matchAll(platformSessionPattern)) {
    const objectBody = match[1];
    const pathMatch = objectBody.match(new RegExp(`path\\s*:\\s*(${stringLiteralPattern})`));
    if (!pathMatch) {
      continue;
    }
    const methodMatch = objectBody.match(/method\s*:\s*["']([A-Z]+)["']/);
    add(methodMatch?.[1] ?? "GET", pathMatch[1]);
  }

  return operations;
};

const buildOpenApiIndex = (openApiFiles, YAML) => {
  const operations = Object.entries(openApiFiles).flatMap(([owner, file]) =>
    parseOpenApiMethodIndex(owner, file, YAML),
  );
  const byMethodAndShape = new Map();

  for (const operation of operations) {
    const key = `${operation.method} ${operation.routeShape}`;
    if (!byMethodAndShape.has(key)) {
      byMethodAndShape.set(key, []);
    }
    byMethodAndShape.get(key).push(operation);
  }

  return { byMethodAndShape, operations };
};

const routeShapeMatches = (openApiRouteShape, cliRouteShape) => {
  const openApiSegments = openApiRouteShape.split("/").filter(Boolean);
  const cliSegments = cliRouteShape.split("/").filter(Boolean);
  if (openApiSegments.length !== cliSegments.length) {
    return false;
  }

  return openApiSegments.every((segment, index) => segment === "{}" || segment === cliSegments[index]);
};

export const collectCliHttpRouteIssues = ({
  routeSources,
  commandSources,
  openApiFiles,
  shippedCommands,
  YAML,
}) => {
  const handlers = readRouteCommandHandlers(routeSources);
  const functions = readExportedFunctionBodies(commandSources);
  const openApiIndex = buildOpenApiIndex(openApiFiles, YAML);
  const issues = [];

  for (const [command, handlerName] of handlers) {
    if (shippedCommands && !shippedCommands.has(command)) {
      continue;
    }

    const handler = functions.get(handlerName);
    if (!handler) {
      continue;
    }

    for (const operation of collectHttpOperationsFromFunctionBody(handler.body)) {
      const key = `${operation.method} ${operation.routeShape}`;
      if (openApiIndex.byMethodAndShape.has(key)) {
        continue;
      }

      if (
        openApiIndex.operations.some((openApiOperation) =>
          openApiOperation.method === operation.method &&
          routeShapeMatches(openApiOperation.routeShape, operation.routeShape)
        )
      ) {
        continue;
      }

      issues.push({
        command,
        handlerName,
        filePath: handler.filePath,
        method: operation.method,
        rawPath: operation.rawPath,
        routeShape: operation.routeShape,
        likelyOwner: probableOwner(operation.routeShape),
      });
    }
  }

  return issues;
};

export const formatCliHttpRouteIssue = (issue, openApiFiles) => {
  const ownerPath = openApiFiles[issue.likelyOwner];
  return [
    `CLI command "${issue.command}" calls missing API operation: ${issue.method} ${issue.routeShape}`,
    `handler: ${issue.handlerName}`,
    `source: ${issue.filePath}`,
    ownerPath ? `owner api-contract: ${ownerPath}` : `owner api-contract: unknown for ${issue.rawPath}`,
  ].join("\n");
};

export const checkCliHttpRouteBindings = ({ root, openApiFiles, shippedCommands, YAML }) => {
  const routeSources = readFilesRecursively(path.join(root, "packages/regents-cli/src/routes"), (filePath) =>
    filePath.endsWith(".ts"),
  ).map((file) => file.source);
  const commandSources = readFilesRecursively(path.join(root, "packages/regents-cli/src/commands"), (filePath) =>
    filePath.endsWith(".ts"),
  );

  return collectCliHttpRouteIssues({
    routeSources,
    commandSources,
    openApiFiles,
    shippedCommands,
    YAML,
  });
};
