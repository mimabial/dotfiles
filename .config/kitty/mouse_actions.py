def handle_result(args, result, target_window_id, boss):
    action = args[1]
    
    if action == 'next_layout':
        boss.active_tab.next_layout()
        return None
    
    if action == 'new_tab':
        boss.launch_tab()
        return None
    
    return None

handle_result.no_ui = True
