import os
import json
from pathlib import Path
from typing import List
from core.matrix.motherboard.ecosystems.tasks.domain.entities import Task

class LocalTaskRepository:
    def __init__(self, config_path: str = ""):
        self.config_path = config_path
        self.directory_path = ""
        self._load_config()

    def _load_config(self):
        if self.config_path and os.path.exists(self.config_path):
            try:
                with open(self.config_path, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                    self.directory_path = config.get("tasks_directory", "")
            except:
                pass
                
    def _save_config(self):
        if self.config_path:
            config = {}
            if os.path.exists(self.config_path):
                try:
                    with open(self.config_path, 'r', encoding='utf-8') as f:
                        config = json.load(f)
                except:
                    pass
            config["tasks_directory"] = self.directory_path
            try:
                with open(self.config_path, 'w', encoding='utf-8') as f:
                    json.dump(config, f, indent=4)
            except:
                pass

    def set_directory(self, path: str):
        self.directory_path = path
        if not os.path.exists(self.directory_path):
            os.makedirs(self.directory_path, exist_ok=True)
        self._save_config()

    def get_all_tasks(self) -> List[Task]:
        self._load_config()
        if not self.directory_path or not os.path.exists(self.directory_path):
            return []
        
        tasks = []
        for filename in os.listdir(self.directory_path):
            if filename.endswith(".task"):
                filepath = os.path.join(self.directory_path, filename)
                try:
                    with open(filepath, 'r', encoding='utf-8') as f:
                        content = f.read()
                        task_id = filename.replace(".task", "")
                        tasks.append(Task.from_markdown(content, task_id))
                except Exception as e:
                    print(f"Error leyendo tarea {filename}: {e}")
        return tasks

    def save_task(self, task: Task):
        if not self.directory_path:
            raise ValueError("Directorio de tareas no configurado.")
            
        filename = f"{task.id}.task"
        filepath = os.path.join(self.directory_path, filename)
        
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(task.to_markdown())
