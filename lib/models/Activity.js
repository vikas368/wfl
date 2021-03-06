// Generated by CoffeeScript 1.3.3

/* 
THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR 
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER 
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN 
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/


(function() {
  var AWS, Activity, Response;

  AWS = require('aws-sdk');

  Response = (function() {

    function Response(swf, token, logger) {
      this.swf = swf;
      this.token = token;
      this.logger = logger;
    }

    Response.prototype.send = function(result, callBack) {
      var swfCfg,
        _this = this;
      if (typeof result !== "string") {
        result = JSON.stringify(result);
      }
      swfCfg = {
        "taskToken": this.token,
        "result": result
      };
      if (callBack == null) {
        callBack = function(err, result) {
          if (err != null) {
            if (err != null) {
              _this.app.logger.error("Error sending activity response", err);
            }
            process.exit(1);
          }
          return _this.logger.verbose("RespondActivityTaskCompleted sent successfully with the following result: " + result + " ");
        };
      }
      this.logger.verbose("Sending activity response to SWF...");
      return this.swf.respondActivityTaskCompleted(swfCfg, callBack);
    };

    Response.prototype.cancel = function(result, callBack) {
      var swfCfg,
        _this = this;
      if (typeof result !== "string") {
        result = JSON.stringify(result);
      }
      swfCfg = {
        "TaskToken": this.token,
        "Details": result
      };
      if (callBack == null) {
        callBack = function(err, result) {
          if (err != null) {
            if (err != null) {
              _this.app.logger.error("Error cancelling activity", err);
            }
            inspect(err, "Error message");
            process.exit(1);
          }
          return _this.logger.verbose("RespondActivityTaskCanceled sent successfully with the following detail: " + result + " ");
        };
      }
      this.logger.verbose("Sending activity response to SWF...");
      return this.swf.RespondActivityTaskCanceled(swfCfg, callBack);
    };

    return Response;

  })();

  Activity = (function() {

    function Activity(app, name, coreFn) {
      var SWF, swfCfg;
      this.app = app;
      this.name = name;
      this.coreFn = coreFn;
      this.taskList = "" + name + "-default-tasklist";
      swfCfg = {
        'accessKeyId': this.app.options.accessKeyId,
        'secretAccessKey': this.app.options.secretAccessKey,
        'region': this.app.options.region
      };
      AWS.config.update(swfCfg);
      SWF = new AWS.SimpleWorkflow;
      this.swf = SWF.client;
    }

    Activity.prototype.poll = function() {
      var request, swfCfg,
        _this = this;
      this.app.logger.verbose("Polling for next task for: " + this.name + " in list:" + this.taskList);
      swfCfg = {
        'domain': this.app.options.domain,
        'taskList': {
          "name": this.taskList
        }
      };
      request = this.swf.pollForActivityTask(swfCfg);
      request.done(function(response) {
        var activityResponse, body, token, _ref, _ref1;
        body = response.data;
        token = body.taskToken;
        if (!(token != null)) {
          return _this.app.logger.verbose("No activity task in the pipe for " + _this.taskList + ", repolling...");
        } else {
          _this.app.logger.verbose("New Activity task received for: " + _this.name + " in list:" + _this.taskList);
          request = {
            name: body.activityType.name,
            id: body.activityId,
            workflowId: body.workflowExecution.workflowId,
            input: "",
            task: body
          };
          try {
            request.input = JSON.parse((_ref = body.input) != null ? _ref : "");
          } catch (e) {
            request.input = (_ref1 = body.input) != null ? _ref1 : {};
          }
          activityResponse = new Response(_this.swf, token, _this.app.logger);
          _this.app.logger.verbose("Start running activity: " + _this.name + " with id: " + request.id + " ");
          return _this.coreFn(request, activityResponse);
        }
      });
      request.fail(function(response) {
        _this.app.logger.error("Unexpected Error polling " + _this.taskList + " ", response.error);
        return process.exit(1);
      });
      return request.always(function(response) {
        return _this.poll();
      });
    };

    return Activity;

  })();

  exports.Activity = Activity;

}).call(this);
