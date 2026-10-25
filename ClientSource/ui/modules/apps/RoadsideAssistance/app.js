angular.module('beamng.apps').directive('roadsideAssistance', ['$interval', '$timeout', function ($interval, $timeout) {
  return {
    restrict: 'EA',
    replace: true,
    scope: {},
    templateUrl: '/ui/modules/apps/RoadsideAssistance/app.html',
    link: function (scope) {
      scope.state = { connected: false, openJobs: [], cooldown: 0 };
      scope.connection = 'Connecting…';
      scope.notice = '';
      scope.busy = false;
      var receivedAt = 0;
      var cooldownUntil = 0;
      var busyTimer;
      var allowed = ['refresh', 'request', 'accept', 'cancel', 'complete', 'release', 'locate', 'unsubscribe'];

      function send(action, jobId) {
        if (allowed.indexOf(action) === -1) return;
        var argument = '';
        if (action === 'accept') {
          if (typeof jobId !== 'number' || !isFinite(jobId) || jobId < 1 || jobId > 2147483647 || Math.floor(jobId) !== jobId) return;
          argument = ', ' + jobId;
        }
        // Only whitelisted ASCII actions and validated integers enter this Lua call.
        bngApi.engineLua('if extensions.roadsideAssist then extensions.roadsideAssist.uiAction("' + action + '"' + argument + ') end');
      }

      scope.act = function (action, jobId) {
        if (scope.busy || (!scope.state.connected && action !== 'refresh')) return;
        scope.busy = true;
        scope.notice = '';
        send(action, jobId);
        $timeout.cancel(busyTimer);
        busyTimer = $timeout(function () { scope.busy = false; }, 2000);
      };
      scope.canTakeJob = function () {
        return scope.state.connected && !scope.busy && !scope.state.request && !scope.state.assignment && !scope.state.selecting;
      };
      scope.canRequest = function () { return scope.canTakeJob() && scope.state.cooldown === 0; };

      scope.$on('RoadsideAssistAppState', function (_, data) {
        scope.$evalAsync(function () {
          data = data || {};
          scope.state = {
            connected: data.connected === true,
            openJobs: Array.isArray(data.openJobs) ? data.openJobs : [],
            playerId: data.playerId,
            request: data.request || null,
            assignment: data.assignment || null,
            selecting: data.selecting === true,
            cooldown: Math.max(0, Number(data.cooldown) || 0)
          };
          receivedAt = Date.now();
          cooldownUntil = receivedAt + scope.state.cooldown * 1000;
          scope.connection = scope.state.connected ? 'Live dispatch' : 'Join a BeamMP server';
          scope.busy = false;
        });
      });
      scope.$on('RoadsideAssistAppNotice', function (_, data) {
        scope.$evalAsync(function () {
          scope.notice = data && typeof data.text === 'string' ? data.text : '';
        });
      });
      var refresh = $interval(function () { send('refresh'); }, 5000);
      var clock = $interval(function () {
        scope.state.cooldown = Math.max(0, Math.ceil((cooldownUntil - Date.now()) / 1000));
        if (!receivedAt || Date.now() - receivedAt > 12000) {
          scope.state.connected = false;
          scope.connection = 'Waiting for server';
        }
      }, 1000);
      var initial = $timeout(function () { send('refresh'); }, 100);
      scope.$on('$destroy', function () {
        $interval.cancel(refresh);
        $interval.cancel(clock);
        $timeout.cancel(initial);
        $timeout.cancel(busyTimer);
        send('unsubscribe');
      });
    }
  };
}]);
