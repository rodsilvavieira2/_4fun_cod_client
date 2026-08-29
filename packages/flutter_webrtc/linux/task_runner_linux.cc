#include "task_runner_linux.h"

#include <glib.h>

namespace flutter_webrtc_plugin {

void TaskRunnerLinux::EnqueueTask(TaskClosure task) {
  {
    std::lock_guard<std::mutex> lock(tasks_mutex_);
    tasks_.push(std::move(task));
  }

  GMainContext* context = g_main_context_default();
  if (context) {
    g_main_context_invoke(
        context,
        [](gpointer user_data)  -> gboolean {
          TaskRunnerLinux* runner = static_cast<TaskRunnerLinux*>(user_data);
          while (true) {
            TaskClosure task;
            {
              std::lock_guard<std::mutex> lock(runner->tasks_mutex_);
              if (runner->tasks_.empty()) {
                break;
              }
              task = std::move(runner->tasks_.front());
              runner->tasks_.pop();
            }

            // Tasks may enqueue another platform task (MethodResultProxy does
            // this when completing an asynchronous method call), so never run
            // user code while holding the queue mutex.
            task();
          }
          return G_SOURCE_REMOVE;
        },
        this);
  }
}

}  // namespace flutter_webrtc_plugin
