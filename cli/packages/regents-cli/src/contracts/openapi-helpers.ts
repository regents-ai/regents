type OperationFor<
  Paths,
  Path extends keyof Paths,
  Method extends keyof Paths[Path],
> = NonNullable<Paths[Path][Method]>;

type JsonContent<Value> = Value extends {
  content: { "application/json": infer Json };
}
  ? Json
  : never;

type SuccessStatusKey = 200 | 201 | 202 | 203 | 204 | 206 | "200" | "201" | "202" | "203" | "204" | "206";

type SuccessResponseUnion<Responses> = Responses extends Record<string | number, unknown>
  ? Responses[Extract<keyof Responses, SuccessStatusKey>]
  : never;

export type JsonRequestBodyFor<
  Paths,
  Path extends keyof Paths,
  Method extends keyof Paths[Path],
> = OperationFor<Paths, Path, Method> extends {
  requestBody: infer RequestBody;
}
  ? JsonContent<RequestBody>
  : never;

export type JsonSuccessResponseFor<
  Paths,
  Path extends keyof Paths,
  Method extends keyof Paths[Path],
> = OperationFor<Paths, Path, Method> extends {
  responses: infer Responses;
}
  ? JsonContent<SuccessResponseUnion<Responses>>
  : never;
