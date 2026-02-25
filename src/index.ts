import { ScreeningWorkflow } from './workflow';

export { ScreeningWorkflow };

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);

    if (url.pathname === '/screen' && req.method === 'POST') {
      const { applicationId, jobId, resumeUrl } = await req.json<{
        applicationId: string;
        jobId: string;
        resumeUrl: string;
      }>();

      const instance = await env.SCREENING_WORKFLOW.create({
        id: `screen-${applicationId}`,
        params: { applicationId, jobId, resumeUrl },
      });

      return Response.json({ instanceId: instance.id });
    }

    return new Response('Not found', { status: 404 });
  },
};
