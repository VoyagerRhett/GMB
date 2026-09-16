import type { Env, SquareNotifyJob } from './types';
import { errorResponse } from './shared/http';
import { routeRequest } from './routes';
import { fanOutPage } from './feeds/notify_fanout';
import { runExpiredMembershipContentCleanup } from './membership/expiration_cleanup';
import { applyCors, cleanupSecurityState } from './security/request_guard';
import { cleanupExpiredUploads } from './uploads/service';
import { cleanupExpiredReservations } from './limits/usage';
import { cleanupExpiredSessionIndexes } from './auth/session_index';
import { reconcileFinalizedUserProjection } from './account/user_projection';
import { reconcileFinalizedSubscriptionProjection } from './membership/subscription_projection';
import { auditSquareR2Consistency } from './media/service';
import { cleanupExpiredPushEndpoints } from './auth/push_endpoint';

type ScheduledJob = {
  readonly name: string;
  readonly run: () => Promise<unknown>;
};

/**
 * 每项定时工作独立结算。清理失败只让本次定时触发失败，不能阻断其他投影或清理。
 */
async function runIndependentScheduledJobs(
  label: string,
  jobs: ReadonlyArray<ScheduledJob>,
): Promise<void> {
  const results = await Promise.allSettled(jobs.map((job) => job.run()));
  const failed = results.flatMap((result, index) =>
    result.status === 'rejected' ? [jobs[index].name] : []
  );
  if (failed.length > 0) {
    throw new Error('[scheduled-' + label + '] failed jobs: ' + failed.join(','));
  }
}
export default {
  async fetch(request: Request, env: Env, _ctx?: ExecutionContext): Promise<Response> {
    try {
      return applyCors(request, env, await routeRequest(request, env));
    } catch (error) {
      return applyCors(request, env, errorResponse(error));
    }
  },

  // 五分钟事件先推进 finalized 身份投影，再通过既有国储会节点隧道推进唯一订阅投影。
  // 手机交易确认仍是即时路径；Cron 统一补齐自动续费、被动状态变化与失败重试。
async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
  let job: Promise<void>;
  if (_controller.cron === '*/5 * * * *') {
    const periodicJobs: ScheduledJob[] = [
      { name: 'cleanup-uploads', run: () => cleanupExpiredUploads(env) },
      { name: 'cleanup-security', run: () => cleanupSecurityState(env) },
      { name: 'cleanup-reservations', run: () => cleanupExpiredReservations(env) },
      { name: 'cleanup-sessions', run: () => cleanupExpiredSessionIndexes(env) },
      { name: 'cleanup-push-endpoints', run: () => cleanupExpiredPushEndpoints(env) },
      { name: 'project-users', run: () => reconcileFinalizedUserProjection(env) },
      { name: 'project-subscriptions', run: () => reconcileFinalizedSubscriptionProjection(env) },
    ];
    if (isDailyCleanupTime(_controller.scheduledTime)) {
      periodicJobs.push({
        name: 'cleanup-expired-membership-content',
        run: () => runExpiredMembershipContentCleanup(env, _controller.scheduledTime),
      });
    }
    job = runIndependentScheduledJobs('periodic', periodicJobs);
  } else if (_controller.cron === '4 3 * * *') {
    job = runIndependentScheduledJobs('r2-audit', [
      { name: 'audit-r2', run: () => auditSquareR2Consistency(env) },
    ]);
  } else {
    job = Promise.reject(new Error('unknown cron: ' + _controller.cron));
  }
  ctx.waitUntil(job);
},

// 广场发帖通知扇出：每条消息 = 一次发帖或一页续跑；fanOutPage 满页会把下一页续跑入队。
  // 单条成功 ack、失败 retry（最多 max_retries），不因一条拖垮整批。
  async queue(batch: MessageBatch<SquareNotifyJob>, env: Env): Promise<void> {
    await Promise.all(
      batch.messages.map(async (message) => {
        try {
          await fanOutPage(env, message.body);
          message.ack();
        } catch (error) {
          console.error(
            `[square-notify] fanout failed: ${error instanceof Error ? error.message : error}`,
          );
          message.retry();
        }
      }),
    );
  }
};

function isDailyCleanupTime(scheduledTime: number): boolean {
  const scheduled = new Date(scheduledTime);
  return scheduled.getUTCHours() === 3 && scheduled.getUTCMinutes() === 0;
}
