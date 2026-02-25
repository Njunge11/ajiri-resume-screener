import {
  WorkflowEntrypoint,
  type WorkflowEvent,
  type WorkflowStep,
} from 'cloudflare:workers';
import type { WorkflowParams } from './types';

// Placeholder types until schemas are built
type JobDescription = Record<string, string>;
type ParsedResume = Record<string, string | string[]>;
type ScreeningResult = {
  score: number;
  recommendation: string;
};

export class ScreeningWorkflow extends WorkflowEntrypoint<Env, WorkflowParams> {
  async run(event: Readonly<WorkflowEvent<WorkflowParams>>, step: WorkflowStep) {
    const { applicationId, jobId, resumeUrl } = event.payload;

    // Step 1: Fetch job description from Next.js API
    const jd = await step.do('fetch-jd', {
      retries: { limit: 3, delay: '5 seconds', backoff: 'exponential' },
      timeout: '30 seconds',
    }, async (): Promise<JobDescription> => {
      const res = await fetch(
        `${this.env.NEXT_API_URL}/api/internal/jobs/${jobId}/jd`,
        { headers: { Authorization: `Bearer ${this.env.INTERNAL_API_SECRET}` } },
      );
      if (!res.ok) throw new Error(`Failed to fetch JD: ${res.status}`);
      return res.json() as Promise<JobDescription>;
    });

    // Step 2: Parse resume
    const parsedResume = await step.do('parse-resume', {
      retries: { limit: 3, delay: '10 seconds', backoff: 'exponential' },
      timeout: '2 minutes',
    }, async (): Promise<ParsedResume> => {
      // TODO: Download resume + call LLM to extract structured data
      throw new Error('Not implemented');
    });

    // Step 3: Score candidate
    const screening = await step.do('score-candidate', {
      retries: { limit: 3, delay: '10 seconds', backoff: 'exponential' },
      timeout: '3 minutes',
    }, async (): Promise<ScreeningResult> => {
      // TODO: Call LLM with parsed resume + JD to produce scores
      throw new Error('Not implemented');
    });

    // Step 4: Store results via Next.js API
    await step.do('store-results', {
      retries: { limit: 3, delay: '5 seconds', backoff: 'exponential' },
      timeout: '30 seconds',
    }, async (): Promise<string> => {
      const res = await fetch(
        `${this.env.NEXT_API_URL}/api/internal/screening/results`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${this.env.INTERNAL_API_SECRET}`,
          },
          body: JSON.stringify({ applicationId, parsedResume, screening }),
        },
      );
      if (!res.ok) throw new Error(`Failed to store results: ${res.status}`);
      return 'ok';
    });

    return { applicationId, recommendation: screening.recommendation };
  }
}
