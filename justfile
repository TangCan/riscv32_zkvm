default:
    just --list

# 分割大文件到指定目录（调用Python脚本实现）
split_into_bak big_file_path:
  #!/usr/bin/env python3
  import os
  import sys
  import hashlib

  # 将相对路径转换为绝对路径
  big_file = os.path.abspath("{{big_file_path}}")

  # 检查文件是否存在
  if not os.path.exists(big_file):
      print(f"错误: 文件 '{big_file}' 不存在", file=sys.stderr)
      sys.exit(1)

  # 检查是否为文件
  if not os.path.isfile(big_file):
      print(f"错误: '{big_file}' 不是一个文件", file=sys.stderr)
      sys.exit(1)

  # 计算原始文件的 MD5 校验和
  try:
      md5_hash = hashlib.md5()
      with open(big_file, "rb") as f:
          for chunk in iter(lambda: f.read(4096), b""):
              md5_hash.update(chunk)
      original_md5 = md5_hash.hexdigest()
  except Exception as e:
      print(f"警告: 无法计算原始文件的 MD5 校验和: {e}", file=sys.stderr)
      original_md5 = "未知"

  # 获取文件大小（用于信息输出）
  try:
      file_size = os.path.getsize(big_file)
  except OSError as e:
      print(f"错误: 无法获取文件大小: {e}", file=sys.stderr)
      sys.exit(1)

  bak_dir = "bak"
  file_dir = os.path.dirname(big_file)
  file_name = os.path.basename(big_file)
  target_dir = os.path.join(bak_dir, file_name)

  # 创建目标目录
  try:
      os.makedirs(target_dir, exist_ok=True)
  except OSError as e:
      print(f"错误: 无法创建目录 '{target_dir}': {e}", file=sys.stderr)
      sys.exit(1)

  # 保存 MD5 校验和到文件
  md5_file = os.path.join(target_dir, f"{file_name}.md5")
  try:
      with open(md5_file, "w") as f:
          f.write(f"{original_md5} *{file_name}\n")
  except Exception as e:
      print(f"警告: 无法保存 MD5 校验和: {e}", file=sys.stderr)

  # 分割文件（每个块10MB）
  chunk_size = 10 * 1024 * 1024  # 10MB
  part_num = 0

  try:
      with open(big_file, 'rb') as f:
          while True:
              chunk = f.read(chunk_size)
              if not chunk:
                  break
              part_num += 1
              part_file = os.path.join(target_dir, f"{file_name}.part{part_num:03d}")
              with open(part_file, 'wb') as p:
                  p.write(chunk)
  except Exception as e:
      print(f"错误: 文件分割失败: {e}", file=sys.stderr)
      sys.exit(1)

  # 输出摘要信息
  print(f"成功: 文件 '{file_name}' ({file_size:,} 字节) 已分割为{part_num}个部分")
  print(f"分割后的文件位于: {os.path.abspath(target_dir)}")
  print(f"原始文件 MD5 校验和: {original_md5}")

# 恢复文件
recover_from_bak:
  #!/usr/bin/env python3
  import os
  import sys
  import glob
  import hashlib

  bak_dir = "bak"

  # 检查bak目录是否存在
  if not os.path.exists(bak_dir) or not os.path.isdir(bak_dir):
      print(f"错误: '{bak_dir}' 目录不存在", file=sys.stderr)
      sys.exit(1)

  # 获取所有可恢复的文件目录
  file_dirs = []
  for item in os.listdir(bak_dir):
      item_path = os.path.join(bak_dir, item)
      if os.path.isdir(item_path):
          # 检查目录下是否有分割文件
          part_files = glob.glob(os.path.join(item_path, "*.*"))
          if part_files:
              file_dirs.append(item)

  if not file_dirs:
      print("错误: 没有找到可恢复的文件", file=sys.stderr)
      sys.exit(1)

  # 显示可恢复文件列表
  print("可恢复的文件列表:")
  for i, file_dir in enumerate(file_dirs, 1):
      print(f"[{i}] {file_dir}")

  # 获取用户选择
  while True:
      try:
          choice = input("\n请选择要恢复的文件编号 (输入q退出): ")
          if choice.lower() == 'q':
              print("操作已取消")
              sys.exit(0)
          
          choice_idx = int(choice) - 1
          if 0 <= choice_idx < len(file_dirs):
              selected_dir = file_dirs[choice_idx]
              break
          else:
              print("错误: 无效的选择，请重试")
      except ValueError:
          print("错误: 请输入有效的数字")

  # 恢复文件
  selected_path = os.path.join(bak_dir, selected_dir)
  output_file = os.path.basename(selected_dir)
  
  # 查找所有部分文件并按编号排序
  part_files = glob.glob(os.path.join(selected_path, f"{output_file}.part*"))
  part_files.sort()

  if not part_files:
      print(f"错误: 在 {selected_path} 中未找到分割文件", file=sys.stderr)
      sys.exit(1)

  # 检查 MD5 文件是否存在
  md5_file = os.path.join(selected_path, f"{output_file}.md5")
  original_md5 = None
  if os.path.exists(md5_file):
      try:
          with open(md5_file, "r") as f:
              original_md5 = f.readline().split()[0]
      except Exception as e:
          print(f"警告: 无法读取 MD5 文件: {e}", file=sys.stderr)

  # 合并文件
  try:
      with open(output_file, 'wb') as outfile:
          for part_file in part_files:
              with open(part_file, 'rb') as infile:
                  outfile.write(infile.read())
  except Exception as e:
      print(f"错误: 文件合并失败: {e}", file=sys.stderr)
      sys.exit(1)

  # 获取恢复后的文件大小
  try:
      file_size = os.path.getsize(output_file)
  except OSError as e:
      print(f"警告: 无法获取恢复后的文件大小: {e}", file=sys.stderr)
      file_size = "未知"

  # 计算恢复文件的 MD5 校验和
  try:
      md5_hash = hashlib.md5()
      with open(output_file, "rb") as f:
          for chunk in iter(lambda: f.read(4096), b""):
              md5_hash.update(chunk)
      recovered_md5 = md5_hash.hexdigest()
  except Exception as e:
      print(f"错误: 无法计算恢复文件的 MD5 校验和: {e}", file=sys.stderr)
      recovered_md5 = "未知"

  # 输出结果
  print(f"\n成功恢复文件: {output_file} ({file_size:,} 字节)")
  print(f"文件已恢复到: {os.path.abspath('.')}")
  
  if original_md5 and recovered_md5:
      print(f"\nMD5 校验和验证:")
      print(f"原始文件: {original_md5}")
      print(f"恢复文件: {recovered_md5}")
      
      if original_md5 == recovered_md5:
          print("\033[92m✓ 校验和匹配，文件恢复完整\033[0m")
      else:
          print("\033[91m✗ 校验和不匹配，文件可能已损坏\033[0m")
  elif recovered_md5:
      print(f"\n恢复文件的 MD5 校验和: {recovered_md5}")
      print("提示: 原始文件的 MD5 校验和不可用，无法验证")

