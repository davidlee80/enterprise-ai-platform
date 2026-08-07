using System;
using System.Threading;

namespace EnterpriseAIPlatform.RuntimeSnapshots
{
    public sealed class AtomicSnapshotSlot
    {
        private object activeSnapshot;

        public object Capture()
        {
            return Interlocked.CompareExchange(ref activeSnapshot, null, null);
        }

        public object Exchange(object candidate)
        {
            if (candidate == null)
            {
                throw new ArgumentNullException("candidate");
            }

            return Interlocked.Exchange(ref activeSnapshot, candidate);
        }
    }
}
