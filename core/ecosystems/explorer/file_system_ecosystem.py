import os
import shutil
from PySide6.QtCore import QDir, QFileInfo

class FileSystemEcosystem:
    """
    Ecosystem responsible for all file system business logic in the Explorer.
    """
    def duplicate_item(self, target_path: str) -> tuple[bool, str]:
        info = QFileInfo(target_path)
        dir_path = info.absolutePath()
        base_name = info.completeBaseName()
        ext = info.suffix()
        ext_str = f".{ext}" if ext else ""
        
        new_name = f"{base_name} (Copia){ext_str}"
        new_path = os.path.join(dir_path, new_name)
        counter = 1
        while os.path.exists(new_path):
            new_name = f"{base_name} (Copia {counter}){ext_str}"
            new_path = os.path.join(dir_path, new_name)
            counter += 1
            
        try:
            if info.isDir():
                shutil.copytree(target_path, new_path)
            else:
                shutil.copy2(target_path, new_path)
            return True, ""
        except Exception as e:
            return False, f"Error al duplicar:\n{e}"
            
    def paste_items(self, clipboard_paths: list[str], clipboard_op: str, target_dir: str) -> tuple[bool, str]:
        try:
            for path in clipboard_paths:
                name = os.path.basename(path)
                dest = os.path.join(target_dir, name)
                if path == dest: continue
                
                if clipboard_op == "copy":
                    if os.path.isdir(path):
                        shutil.copytree(path, dest, dirs_exist_ok=True)
                    else:
                        shutil.copy2(path, dest)
                elif clipboard_op == "cut":
                    shutil.move(path, dest)
            return True, ""
        except Exception as e:
            return False, f"Error pasting {name}:\n{e}"
            
    def delete_items(self, paths: list[str]) -> tuple[bool, str]:
        for path in paths:
            try:
                info = QFileInfo(path)
                if info.isDir():
                    shutil.rmtree(path)
                else:
                    os.remove(path)
            except Exception as e:
                return False, f"Error al borrar {os.path.basename(path)}: {str(e)}"
        return True, ""

    def create_folder(self, parent_dir: str, name: str) -> tuple[bool, str]:
        if not QDir(parent_dir).mkdir(name):
            return False, "No se pudo crear la carpeta."
        return True, ""
        
    def create_file(self, parent_dir: str, name: str) -> tuple[bool, str]:
        file_path = os.path.join(parent_dir, name)
        try:
            with open(file_path, 'w') as f:
                pass
            return True, ""
        except Exception as e:
            return False, f"Error al crear archivo: {e}"
            
    def rename_item(self, target_path: str, new_path: str) -> tuple[bool, str]:
        try:
            os.rename(target_path, new_path)
            return True, ""
        except Exception as e:
            return False, f"No se pudo renombrar: {e}"
