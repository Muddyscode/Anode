// The measurement-model contract as JSON Schema, for the Python model server (model/).
import { z } from "zod";
import { MeasureRequest, MeasureResponse } from "./findings";

export function measureSchemas(): Record<string, unknown> {
  return {
    "measure-request.json": z.toJSONSchema(MeasureRequest),
    "measure-response.json": z.toJSONSchema(MeasureResponse),
  };
}
