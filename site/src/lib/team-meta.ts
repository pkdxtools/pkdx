import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { z } from 'zod';

const baseStatsSchema = z.object({
  h: z.number(),
  a: z.number(),
  b: z.number(),
  c: z.number(),
  d: z.number(),
  s: z.number(),
});

const moveSchema = z.object({
  name: z.string(),
  type: z.string(),
  category: z.string(),
  power: z.number().optional(),
  accuracy: z.number().optional(),
});

const memberSchema = z.object({
  name: z.string(),
  types: z.array(z.string()).default([]),
  base_stats: baseStatsSchema.optional(),
  ability: z.string().optional(),
  item: z.string().optional(),
  role: z.string().optional(),
  nature: z.string().nullable().optional(),
  stat_points: baseStatsSchema.nullable().optional(),
  actual_stats: baseStatsSchema.nullable().optional(),
  ivs: baseStatsSchema.nullable().optional(),
  moves: z.array(moveSchema).default([]),
});

const coverageRowSchema = z.object({
  defending_type: z.string(),
  best_move_type: z.string().optional(),
  user: z.string().optional(),
  multiplier: z.number().optional(),
});

const defenseMatrixRowSchema = z.object({
  attack_type: z.string(),
  multipliers: z.array(z.number()).optional(),
  best_switch: z.string().optional(),
});

const matchupPlanSchema = z.object({
  opponent: z.string(),
  selection: z.array(z.string()).optional(),
  leads: z.array(z.string()).optional(),
  backs: z.array(z.string()).optional(),
  note: z.string().optional(),
});

const statLineSchema = z.object({
  name: z.string().optional(),
  level: z.number().optional(),
  ability: z.string().optional(),
  item: z.string().optional(),
  nature: z.string().optional(),
  tera_type: z.string().optional(),
  hp_stat: z.number().optional(),
  stats: baseStatsSchema.partial().optional(),
  ranks: z.record(z.string(), z.number()).optional(),
});

const damageCalcSchema = z.object({
  title: z.string().optional(),
  attacker: statLineSchema,
  defender: statLineSchema,
  move: z.object({
    name: z.string(),
    type: z.string(),
    category: z.string(),
    power: z.number().optional(),
  }),
  conditions: z
    .object({
      weather: z.string().optional(),
      field: z.string().optional(),
      crit: z.boolean().optional(),
    })
    .optional(),
  rolls_percent: z.array(z.number()).default([]),
  min_percent: z.number().optional(),
  max_percent: z.number().optional(),
  guaranteed_hits: z.number().optional(),
  note: z.string().optional(),
});

export const teamMetaSchema = z.object({
  battle_format: z.string().optional(),
  mechanics: z.string().optional(),
  version: z.string().optional(),
  regulation: z.string().optional(),
  phase: z.number().optional(),
  members: z.array(memberSchema).default([]),
  coverage: z.array(coverageRowSchema).default([]),
  defense_matrix: z.array(defenseMatrixRowSchema).default([]),
  matchup_plans: z.array(matchupPlanSchema).default([]),
  strengths: z.array(z.string()).default([]),
  weaknesses: z.array(z.string()).default([]),
  damage_calcs: z.array(damageCalcSchema).default([]),
  updated_at: z.string().optional(),
  schema_version: z.number().optional(),
});

export type TeamMeta = z.infer<typeof teamMetaSchema>;
export type TeamMember = z.infer<typeof memberSchema>;
export type CoverageRow = z.infer<typeof coverageRowSchema>;
export type DefenseMatrixRow = z.infer<typeof defenseMatrixRowSchema>;
export type MatchupPlan = z.infer<typeof matchupPlanSchema>;
export type DamageCalc = z.infer<typeof damageCalcSchema>;

export function parseTeamMeta(jsonText: string | null): TeamMeta | null {
  if (!jsonText) return null;
  let raw: unknown;
  try {
    raw = JSON.parse(jsonText);
  } catch {
    return null;
  }
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    return null;
  }
  const result = teamMetaSchema.safeParse(raw);
  return result.success ? result.data : null;
}

export function loadTeamMeta(slug: string): TeamMeta | null {
  try {
    const base = process.env.CONTENT_ROOT ?? '../box';
    const candidate = resolve(process.cwd(), `${base}/teams/${slug}.meta.json`);
    if (!existsSync(candidate)) return null;
    const text = readFileSync(candidate, 'utf-8');
    return parseTeamMeta(text);
  } catch {
    return null;
  }
}
