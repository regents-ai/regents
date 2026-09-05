import { readFile } from "node:fs/promises";

import { CliUsageError } from "../cli-usage-error.js";
import { getFlag, requireArg, type ParsedCliArgs } from "../parse.js";
import { printJson } from "../printer.js";
import { loadResolvedPlatformSession, requestPlatformSessionJson } from "./platform.js";

type HttpMethod = "GET" | "POST" | "PUT";
type JsonObject = Record<string, unknown>;
type RegentServiceKind = "research" | "question_forge";

export async function runServiceInit(args: ParsedCliArgs): Promise<void> {
  const slug = requireServiceSlug(args);
  const serviceSlug = requireServiceDefinitionSlug(args);
  const kind = parseServiceKind(args);
  const skillPackage = parseSkillPackage(args, kind);
  const schema = await readJsonObject(requireArg(getFlag(args, "schema-file"), "schema-file"));
  const { origin, session } = await loadResolvedPlatformSession(args);

  await requestServiceCommand(args, {
    origin,
    session,
    command: "regents service init",
    method: "POST",
    path: `/api/platform/agents/${slug}/service-definitions`,
    body: {
      service_slug: serviceSlug,
      kind,
      ...(skillPackage ? { skill_package: skillPackage } : {}),
      card: {
        slug: serviceSlug,
        name: requireArg(getFlag(args, "name"), "name"),
        summary: requireArg(getFlag(args, "summary"), "summary"),
        price_label: requireArg(getFlag(args, "price-label"), "price-label"),
        payment_rail: "x402",
        delivery_mode: "async_result",
        public_result_default: false,
      },
      schema,
      rwr_template: requireArg(getFlag(args, "rwr-template"), "rwr-template"),
    },
  });
}

export async function runServiceTest(args: ParsedCliArgs): Promise<void> {
  const slug = requireServiceSlug(args);
  const serviceSlug = requireServiceDefinitionSlug(args);
  const inputFile = getFlag(args, "input-file");
  const { origin, session } = await loadResolvedPlatformSession(args);

  await requestServiceCommand(args, {
    origin,
    session,
    command: "regents service test",
    method: "POST",
    path: `/api/platform/agents/${slug}/service-definitions/${serviceSlug}/sandbox-test`,
    body: inputFile ? { input: await readJsonObject(inputFile) } : {},
  });
}

export async function runServicePriceSet(args: ParsedCliArgs): Promise<void> {
  const slug = requireServiceSlug(args);
  const serviceSlug = requireServiceDefinitionSlug(args);
  const { origin, session } = await loadResolvedPlatformSession(args);

  await requestServiceCommand(args, {
    origin,
    session,
    command: "regents service price set",
    method: "PUT",
    path: `/api/platform/agents/${slug}/service-definitions/${serviceSlug}/pricing`,
    body: {
      payment: {
        currency: "USDC",
        amount: requireArg(getFlag(args, "amount-usdc"), "amount-usdc"),
        network: requireArg(getFlag(args, "network"), "network"),
        settlement_asset: requireArg(getFlag(args, "settlement-asset"), "settlement-asset"),
        pay_to: requireArg(getFlag(args, "pay-to"), "pay-to"),
        payment_protocol: "x402",
        quote_ttl_seconds: 300,
      },
    },
  });
}

export async function runServicePublish(args: ParsedCliArgs): Promise<void> {
  await requestServiceAction(args, "regents service publish", "publish");
}

export async function runServicePause(args: ParsedCliArgs): Promise<void> {
  await requestServiceAction(args, "regents service pause", "pause");
}

export async function runServiceResume(args: ParsedCliArgs): Promise<void> {
  await requestServiceAction(args, "regents service resume", "resume");
}

export async function runServiceRuns(args: ParsedCliArgs): Promise<void> {
  const slug = requireServiceSlug(args);
  const serviceSlug = requireServiceDefinitionSlug(args);
  const { origin, session } = await loadResolvedPlatformSession(args);

  await requestServiceCommand(args, {
    origin,
    session,
    command: "regents service runs",
    method: "GET",
    path: `/api/platform/agents/${slug}/service-definitions/${serviceSlug}/invocations`,
  });
}

export async function runServiceLogs(args: ParsedCliArgs): Promise<void> {
  const slug = requireServiceSlug(args);
  const serviceSlug = requireServiceDefinitionSlug(args);
  const { origin, session } = await loadResolvedPlatformSession(args);

  await requestServiceCommand(args, {
    origin,
    session,
    command: "regents service logs",
    method: "GET",
    path: `/api/platform/agents/${slug}/service-definitions/${serviceSlug}/invocations`,
  });
}

export async function runServiceCatalogCheck(args: ParsedCliArgs): Promise<void> {
  const slug = requireServiceSlug(args);
  const serviceSlug = requireServiceDefinitionSlug(args);
  const { origin, session } = await loadResolvedPlatformSession(args);

  await requestServiceCommand(args, {
    origin,
    session,
    command: "regents service catalog check",
    method: "GET",
    path: `/api/platform/agents/${slug}/service-definitions/${serviceSlug}/catalog-readiness`,
  });
}

const requestServiceAction = async (
  args: ParsedCliArgs,
  command: string,
  action: "publish" | "pause" | "resume",
): Promise<void> => {
  const slug = requireServiceSlug(args);
  const serviceSlug = requireServiceDefinitionSlug(args);
  const { origin, session } = await loadResolvedPlatformSession(args);

  await requestServiceCommand(args, {
    origin,
    session,
    command,
    method: "POST",
    path: `/api/platform/agents/${slug}/service-definitions/${serviceSlug}/${action}`,
  });
};

const requestServiceCommand = async (
  args: ParsedCliArgs,
  options: {
    readonly origin: string;
    readonly session: Awaited<ReturnType<typeof loadResolvedPlatformSession>>["session"];
    readonly command: string;
    readonly method: HttpMethod;
    readonly path: string;
    readonly body?: JsonObject;
  },
): Promise<void> => {
  const { data } = await requestPlatformSessionJson({
    origin: options.origin,
    session: options.session,
    method: options.method,
    path: options.path,
    body: options.body,
    commandName: options.command,
    configPath: getFlag(args, "config"),
  });

  printJson({
    ok: true,
    command: options.command,
    origin: options.origin,
    result: data,
  });
};

const requireServiceSlug = (args: ParsedCliArgs): string =>
  encodeURIComponent(requireArg(getFlag(args, "slug"), "slug"));

const requireServiceDefinitionSlug = (args: ParsedCliArgs): string =>
  encodeURIComponent(requireArg(getFlag(args, "service-slug"), "service-slug"));

const parseServiceKind = (args: ParsedCliArgs): RegentServiceKind => {
  const value = getFlag(args, "kind") ?? "research";

  if (value === "research") {
    return "research";
  }

  if (value === "question-forge") {
    return "question_forge";
  }

  throw new CliUsageError({
    code: "invalid_flag_value",
    message: "--kind must be research or question-forge.",
  });
};

const parseSkillPackage = (
  args: ParsedCliArgs,
  kind: RegentServiceKind,
): JsonObject | undefined => {
  const id = getFlag(args, "skill-package");
  const version = getFlag(args, "skill-package-version");

  if (kind === "question_forge" && (!id || !version)) {
    throw new CliUsageError({
      code: "missing_required_argument",
      message: "--skill-package and --skill-package-version are required when --kind question-forge.",
      missing: [
        ...(id ? [] : ["--skill-package"]),
        ...(version ? [] : ["--skill-package-version"]),
      ],
    });
  }

  if ((id && !version) || (!id && version)) {
    throw new CliUsageError({
      code: "missing_required_argument",
      message: "--skill-package and --skill-package-version must be passed together.",
      missing: [
        ...(id ? [] : ["--skill-package"]),
        ...(version ? [] : ["--skill-package-version"]),
      ],
    });
  }

  return id && version ? { id, version } : undefined;
};

const readJsonObject = async (filePath: string): Promise<JsonObject> => {
  const parsed = JSON.parse(await readFile(filePath, "utf8")) as unknown;

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new CliUsageError({
      code: "invalid_json_file",
      message: `${filePath} must contain a JSON object.`,
    });
  }

  return parsed as JsonObject;
};
